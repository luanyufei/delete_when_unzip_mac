import Foundation
import Clibarchive

private final class LibArchiveReadContext {
    let source: StreamDataSource
    let internalBuffer: UnsafeMutablePointer<UInt8>
    let bufferCapacity: Int = 1024 * 1024 // 1MB 读缓冲区

    init(source: StreamDataSource) {
        self.source = source
        self.internalBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferCapacity)
    }

    func readNextChunk(into bufferPtr: UnsafeMutablePointer<UnsafeRawPointer?>?) -> Int {
        guard let bufferPtr = bufferPtr else { return -1 }
        do {
            let bytesRead = try source.read(into: internalBuffer, maxLength: bufferCapacity)
            if bytesRead > 0 {
                bufferPtr.pointee = UnsafeRawPointer(internalBuffer)
                return bytesRead
            } else {
                bufferPtr.pointee = nil
                return 0 // EOF
            }
        } catch {
            return -1
        }
    }

    deinit {
        internalBuffer.deallocate()
    }
}

// C 回调函数
private func archiveReadCallback(
    _ archive: OpaquePointer?,
    _ clientData: UnsafeMutableRawPointer?,
    _ buffer: UnsafeMutablePointer<UnsafeRawPointer?>?
) -> Int {
    guard let clientData = clientData else { return -1 }
    let context = Unmanaged<LibArchiveReadContext>.fromOpaque(clientData).takeUnretainedValue()
    return context.readNextChunk(into: buffer)
}

private func archiveCloseCallback(
    _ archive: OpaquePointer?,
    _ clientData: UnsafeMutableRawPointer?
) -> Int32 {
    guard let clientData = clientData else { return 0 }
    let context = Unmanaged<LibArchiveReadContext>.fromOpaque(clientData).takeUnretainedValue()
    context.source.close()
    return 0
}

public final class LibArchiveExtractor: Extractor, @unchecked Sendable {

    public init() {}

    public func extract(
        source: StreamDataSource,
        to outputDirectory: URL,
        password: String? = nil,
        progressHandler: @escaping @Sendable (ExtractionProgress) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let archive = archive_read_new()
        guard let archive = archive else {
            throw ExtractionError.archiveOpenFailed("无法分配 libarchive 读取结构体")
        }
        defer { archive_read_free(archive) }

        archive_read_support_filter_all(archive)
        archive_read_support_format_all(archive)

        if let pwd = password, !pwd.isEmpty {
            archive_read_add_passphrase(archive, pwd)
        }

        let context = LibArchiveReadContext(source: source)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        defer { Unmanaged<LibArchiveReadContext>.fromOpaque(contextPtr).release() }

        archive_read_set_callback_data(archive, contextPtr)
        archive_read_set_read_callback(archive, archiveReadCallback)
        archive_read_set_close_callback(archive, archiveCloseCallback)

        let openStatus = archive_read_open1(archive)
        guard openStatus == ARCHIVE_OK else {
            let errorMsg = archive_error_string(archive).map { String(cString: $0) } ?? "未知错误"
            throw ExtractionError.archiveOpenFailed(errorMsg)
        }

        var entry: OpaquePointer?
        let totalSize = source.totalSize

        while true {
            try Task.checkCancellation()

            let headerStatus = archive_read_next_header(archive, &entry)
            if headerStatus == ARCHIVE_EOF {
                break
            }
            if headerStatus != ARCHIVE_OK {
                let errorMsg = archive_error_string(archive).map { String(cString: $0) } ?? "读取条目头错误"
                if errorMsg.contains("Passphrase") || errorMsg.contains("password") {
                    throw ExtractionError.wrongPassword
                }
                throw ExtractionError.readDataFailed(errorMsg)
            }

            guard let entry = entry else { continue }

            let rawPathName: String
            if let pathnameUTF8 = archive_entry_pathname_utf8(entry) {
                rawPathName = String(cString: pathnameUTF8)
            } else if let pathname = archive_entry_pathname(entry) {
                rawPathName = FileNameDecoder.decode(cString: pathname)
            } else {
                rawPathName = "unnamed_\(UUID().uuidString)"
            }

            // 防止 Zip Slip 路径穿越安全漏洞
            let cleanRelativePath = (rawPathName as NSString).standardizingPath
            if cleanRelativePath.hasPrefix("../") || cleanRelativePath == ".." {
                continue
            }

            let destinationURL = outputDirectory.appendingPathComponent(cleanRelativePath)
            let fileType = archive_entry_filetype(entry)
            let isDirectory = (fileType & mode_t(S_IFMT)) == mode_t(S_IFDIR) || fileType == 0o040000 || cleanRelativePath.hasSuffix("/")

            if isDirectory {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else {
                let parentDir = destinationURL.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

                // 创建并写入目标文件
                fileManager.createFile(atPath: destinationURL.path, contents: nil)
                guard let writeHandle = try? FileHandle(forWritingTo: destinationURL) else {
                    throw ExtractionError.writeDataFailed("无法打开写入目标文件: \(destinationURL.path)")
                }

                var writeBuffer = [UInt8](repeating: 0, count: 65536)
                while true {
                    try Task.checkCancellation()

                    let bytesRead = archive_read_data(archive, &writeBuffer, writeBuffer.count)
                    if bytesRead == 0 {
                        break
                    }
                    if bytesRead < 0 {
                        let errStr = archive_error_string(archive).map { String(cString: $0) } ?? "数据块解压失败"
                        try? writeHandle.close()
                        throw ExtractionError.readDataFailed(errStr)
                    }

                    writeHandle.write(Data(bytes: writeBuffer, count: bytesRead))

                    let consumed = source.consumedBytes
                    let progressValue = totalSize > 0 ? min(1.0, Double(consumed) / Double(totalSize)) : 0.0
                    progressHandler(ExtractionProgress(
                        progress: progressValue,
                        currentFileName: (cleanRelativePath as NSString).lastPathComponent,
                        processedBytes: consumed,
                        totalBytes: totalSize
                    ))
                }

                try? writeHandle.close()
            }
        }

        // 最终报告 100% 进度
        progressHandler(ExtractionProgress(
            progress: 1.0,
            currentFileName: "完成",
            processedBytes: totalSize,
            totalBytes: totalSize
        ))
    }
}
