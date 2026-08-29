import Foundation

public protocol StreamDataSource: AnyObject {
    var totalSize: UInt64 { get }
    var consumedBytes: UInt64 { get }
    /// 是否支持随机访问寻址 (7z 等尾部头信息格式需要)
    var supportsRandomAccess: Bool { get }
    func read(into buffer: UnsafeMutablePointer<UInt8>, maxLength: Int) throws -> Int
    /// 寻址到指定逻辑偏移，返回新偏移；失败返回 -1
    func seek(toOffset: off_t) -> off_t
    func close()
    func finalizeAndRemove()
}

public extension StreamDataSource {
    var supportsRandomAccess: Bool { false }
    func seek(toOffset: off_t) -> off_t { -1 }
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
            // 顺序策略下读到 0 字节即真实 EOF; 随机访问策略 (.none/7z) 会探测性读取
            // 文件末尾，此处严禁销毁源文件 —— 成功结束时由 extractor 统一 finalizeAndRemove
            if strategy != .none {
                finalizeAndRemove()
            }
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

    /// 仅 .none 策略 (7z 等需随机访问的格式) 支持寻址:
    /// 打洞与平移截断均已物理销毁已读数据，向后寻址必然读到空洞
    public var supportsRandomAccess: Bool { strategy == .none }

    public func seek(toOffset target: off_t) -> off_t {
        guard supportsRandomAccess, !isClosed, fd >= 0,
              target >= 0, target <= off_t(totalSize) else { return -1 }
        readOffset = target
        return target
    }

    public func finalizeAndRemove() {
        close()
        try? FileManager.default.removeItem(at: fileURL)
    }

    deinit {
        close()
    }
}
