import Foundation

public protocol StreamDataSource: AnyObject {
    var totalSize: UInt64 { get }
    var consumedBytes: UInt64 { get }
    func read(into buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) throws -> Int
    func close()
    func finalizeAndRemove()
}

public final class ChunkReader: StreamDataSource {
    public let fileURL: URL
    public let chunkSize: Int
    public let strategy: ReclaimStrategy
    public private(set) var totalSize: UInt64 = 0
    public private(set) var consumedBytes: UInt64 = 0

    private var fileHandle: FileHandle?
    private var fd: Int32 = -1
    private var readOffset: off_t = 0
    private var lastPunchedOffset: off_t = 0
    private var isClosed = false

    public init(fileURL: URL, chunkSize: Int = 10 * 1024 * 1024, strategy: ReclaimStrategy? = nil) throws {
        self.fileURL = fileURL
        self.chunkSize = max(64 * 1024, chunkSize)
        self.strategy = strategy ?? SpaceReclaimer.detectStrategy(for: fileURL)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ExtractionError.fileNotFound(fileURL)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.totalSize = (attrs[.size] as? UInt64) ?? 0

        let handle = try FileHandle(forUpdating: fileURL)
        self.fileHandle = handle
        self.fd = handle.fileDescriptor
    }

    public func read(into buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) throws -> Int {
        guard !isClosed, fd >= 0 else { return 0 }

        let bytesToRead = min(maxLength, chunkSize)
        var bytesRead: Int = 0

        switch strategy {
        case .punchHole:
            bytesRead = pread(fd, buffer, bytesToRead, readOffset)
            if bytesRead > 0 {
                readOffset += off_t(bytesRead)
                consumedBytes += UInt64(bytesRead)

                // 保持安全边距：当已读数据超过 2 个 chunk 时，将较早的已消费物理块打洞释放
                let punchableLength = readOffset - lastPunchedOffset - off_t(chunkSize)
                if punchableLength >= off_t(chunkSize) {
                    try? SpaceReclaimer.punchHole(fd: fd, offset: lastPunchedOffset, length: punchableLength)
                    lastPunchedOffset += punchableLength
                }
            }

        case .shiftTruncate:
            bytesRead = pread(fd, buffer, bytesToRead, 0)
            if bytesRead > 0 {
                consumedBytes += UInt64(bytesRead)
                if let handle = fileHandle {
                    try? SpaceReclaimer.shiftThenTruncate(handle: handle, chunkSize: bytesRead)
                }
            }

        case .none:
            bytesRead = pread(fd, buffer, bytesToRead, readOffset)
            if bytesRead > 0 {
                readOffset += off_t(bytesRead)
                consumedBytes += UInt64(bytesRead)
            }
        }

        if bytesRead == 0 {
            // 到达文件末尾，清理并删除原文件
            finalizeAndRemove()
        }

        return bytesRead
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        if let handle = fileHandle {
            try? handle.close()
            fileHandle = nil
        }
        fd = -1
    }

    public func finalizeAndRemove() {
        close()
        try? FileManager.default.removeItem(at: fileURL)
    }

    deinit {
        close()
    }
}
