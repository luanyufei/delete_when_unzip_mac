import Foundation

public final class VolumeChainReader: StreamDataSource {
    public let volumeURLs: [URL]
    public let chunkSize: Int
    public private(set) var totalSize: UInt64 = 0
    public private(set) var consumedBytes: UInt64 = 0

    private var currentIndex: Int = 0
    private var currentHandle: FileHandle?
    private var currentFd: Int32 = -1
    private var currentOffset: off_t = 0
    private var isClosed = false

    public init(volumes: [URL], chunkSize: Int = 10 * 1024 * 1024) throws {
        guard !volumes.isEmpty else {
            throw ExtractionError.invalidVolumeSequence("分卷列表为空")
        }
        self.volumeURLs = volumes
        self.chunkSize = max(64 * 1024, chunkSize)

        var total: UInt64 = 0
        for url in volumes {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        self.totalSize = total

        try openVolume(at: 0)
    }

    private func openVolume(at index: Int) throws {
        guard index < volumeURLs.count else {
            currentHandle = nil
            currentFd = -1
            return
        }

        let url = volumeURLs[index]
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExtractionError.fileNotFound(url)
        }

        let handle = try FileHandle(forReadingFrom: url)
        self.currentHandle = handle
        self.currentFd = handle.fileDescriptor
        self.currentOffset = 0

        // .z01 或 .Z01 分卷在作为 ZIP 流拼接时，如果处于首个分卷需要跳过 4 字节魔数
        let ext = url.pathExtension.lowercased()
        if ext == "z01" && index == 0 {
            currentOffset = 4
        }
    }

    public func read(into buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) throws -> Int {
        guard !isClosed else { return 0 }

        while currentIndex < volumeURLs.count {
            if currentFd < 0 {
                try openVolume(at: currentIndex)
                if currentFd < 0 { return 0 }
            }

            let bytesToRead = min(maxLength, chunkSize)
            let bytesRead = pread(currentFd, buffer, bytesToRead, currentOffset)

            if bytesRead > 0 {
                currentOffset += off_t(bytesRead)
                consumedBytes += UInt64(bytesRead)
                return bytesRead
            } else {
                // 当前分卷读取完毕 -> 关闭句柄并删除该分卷文件
                let finishedURL = volumeURLs[currentIndex]
                currentHandle?.closeFile()
                currentHandle = nil
                currentFd = -1

                try? FileManager.default.removeItem(at: finishedURL)

                currentIndex += 1
                if currentIndex < volumeURLs.count {
                    try openVolume(at: currentIndex)
                }
            }
        }

        return 0
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        if let handle = currentHandle {
            handle.closeFile()
            currentHandle = nil
        }
        currentFd = -1
    }

    deinit {
        close()
    }
}
