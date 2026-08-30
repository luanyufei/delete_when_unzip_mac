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
    /// 延迟打洞 (7z): libarchive 解析头部时需要回跳 seek，首次回跳前禁止打洞；
    /// 进入顺序消费阶段后再正常边读边释放。仅对打洞策略生效。
    public let punchAfterSeek: Bool
    public private(set) var totalSize: UInt64 = 0
    public private(set) var consumedBytes: UInt64 = 0

    private var fileHandle: FileHandle?
    private var fd: Int32 = -1
    private var readOffset: off_t = 0
    private var lastPunchedOffset: off_t = 0
    private var isClosed = false
    private var seekPhaseArmed = false

    public init(fileURL: URL, chunkSize: Int = 10 * 1024 * 1024,
                strategy: ReclaimStrategy? = nil, punchAfterSeek: Bool = false) throws {
        self.fileURL = fileURL
        self.chunkSize = max(64 * 1024, chunkSize)
        self.strategy = strategy ?? SpaceReclaimer.detectStrategy(for: fileURL)
        self.punchAfterSeek = punchAfterSeek

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ExtractionError.fileNotFound(fileURL)
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        self.totalSize = (attrs[.size] as? UInt64) ?? 0

        let handle = try FileHandle(forUpdating: fileURL)
        self.fileHandle = handle
        self.fd = handle.fileDescriptor
    }

    private var punchingActive: Bool {
        strategy == .punchHole && (!punchAfterSeek || seekPhaseArmed)
    }

    /// 供外部模块 (测试/工具) 使用的标准构造入口，避免跨模块默认参数符号问题
    public static func make(fileURL: URL, chunkSize: Int) throws -> ChunkReader {
        try ChunkReader(fileURL: fileURL, chunkSize: chunkSize)
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
                if punchingActive {
                    let punchableLength = readOffset - lastPunchedOffset - off_t(chunkSize)
                    if punchableLength >= off_t(chunkSize) {
                        try? SpaceReclaimer.punchHole(fd: fd, offset: lastPunchedOffset, length: punchableLength)
                        lastPunchedOffset += punchableLength
                    }
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
            // 顺序策略下读到 0 字节即真实 EOF; 随机访问策略 (.none / 延迟打洞) 会探测性读取
            // 文件末尾，此处严禁销毁源文件 —— 成功结束时由 extractor 统一 finalizeAndRemove
            if !supportsRandomAccess {
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

    /// .none 完全随机访问; 延迟打洞模式允许寻址，但仅限未打洞区域
    public var supportsRandomAccess: Bool {
        if strategy == .none { return true }
        if strategy == .punchHole && punchAfterSeek { return true }
        return false
    }

    public func seek(toOffset target: off_t) -> off_t {
        guard supportsRandomAccess, !isClosed, fd >= 0,
              target >= 0, target <= off_t(totalSize) else { return -1 }
        if target < lastPunchedOffset {
            // 回跳进入已打洞区域 —— 数据已被物理释放，明确失败优于静默损坏
            return -1
        }
        // 仅认可"深回跳"为头部解析完成的信号 (7z: 从文件尾跳回起始头部，
        // 幅度巨大)。数据阶段的微小回退 (libarchive 缓冲抖动，<1MB) 不放行打洞，
        // 由 2 chunk 安全边距兜底。
        if !seekPhaseArmed, target < readOffset - max(64 * 1024 * 1024, off_t(4) * off_t(chunkSize)) {
            seekPhaseArmed = true
        }
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
