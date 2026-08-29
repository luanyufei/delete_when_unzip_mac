import Foundation

public final class VolumeChainReader: StreamDataSource {
    public let volumeURLs: [URL]
    public let chunkSize: Int
    /// 7z 等需随机访问的格式必须关闭逐卷删除，否则已删分卷无法回退寻址
    public let deletesVolumesAsRead: Bool
    public private(set) var totalSize: UInt64 = 0
    public private(set) var consumedBytes: UInt64 = 0

    private var currentIndex: Int = 0
    private var currentHandle: FileHandle?
    private var currentFd: Int32 = -1
    private var currentOffset: off_t = 0
    private var isClosed = false
    /// 每卷在逻辑流中的起始偏移（已扣除首卷 .z01 的 4 字节魔数）
    private var volumeStarts: [off_t] = []
    private var volumeSkips: [off_t] = []

    public init(volumes: [URL], chunkSize: Int = 10 * 1024 * 1024, deletesVolumesAsRead: Bool = true) throws {
        guard !volumes.isEmpty else {
            throw ExtractionError.invalidVolumeSequence("分卷列表为空")
        }
        self.volumeURLs = volumes
        self.chunkSize = max(64 * 1024, chunkSize)
        self.deletesVolumesAsRead = deletesVolumesAsRead

        var total: UInt64 = 0
        var logical: off_t = 0
        var starts: [off_t] = []
        var skips: [off_t] = []
        for url in volumes {
            var size: UInt64 = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let s = attrs[.size] as? UInt64 {
                size = s
            }
            let skip: off_t = (url.pathExtension.lowercased() == "z01" && starts.isEmpty) ? 4 : 0
            starts.append(logical)
            skips.append(skip)
            logical += off_t(size) - skip
            total += size
        }
        self.totalSize = total
        self.volumeStarts = starts
        self.volumeSkips = skips

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
                // 当前分卷读取完毕 -> 关闭句柄; 允许时立即物理删除该分卷释放整卷空间
                let finishedURL = volumeURLs[currentIndex]
                currentHandle?.closeFile()
                currentHandle = nil
                currentFd = -1

                if deletesVolumesAsRead {
                    try? FileManager.default.removeItem(at: finishedURL)
                }

                currentIndex += 1
                if currentIndex < volumeURLs.count {
                    try openVolume(at: currentIndex)
                }
            }
        }

        return 0
    }

    public var supportsRandomAccess: Bool { !deletesVolumesAsRead }

    /// 跨卷寻址: 将逻辑流偏移换算为 (卷索引, 卷内偏移) 并重定位
    public func seek(toOffset target: off_t) -> off_t {
        guard supportsRandomAccess, !isClosed,
              target >= 0, target <= off_t(totalSize) else { return -1 }

        var index = 0
        while index < volumeStarts.count - 1 && target >= volumeStarts[index + 1] {
            index += 1
        }

        if index != currentIndex || currentFd < 0 {
            guard index < volumeURLs.count,
                  FileManager.default.fileExists(atPath: volumeURLs[index].path) else { return -1 }
            currentHandle?.closeFile()
            currentHandle = nil
            currentFd = -1
            do {
                try openVolume(at: index)
            } catch {
                return -1
            }
            currentIndex = index
        }

        currentOffset = target - volumeStarts[index] + volumeSkips[index]
        return target
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

    public func finalizeAndRemove() {
        close()
        for url in volumeURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    deinit {
        close()
    }
}
