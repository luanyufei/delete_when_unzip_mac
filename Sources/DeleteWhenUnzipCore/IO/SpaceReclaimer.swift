import Foundation
import Darwin

public enum ReclaimStrategy: Sendable {
    case punchHole      // APFS 原生打洞 (O(1) 释放，零额外 IO)
    case shiftTruncate  // 通用回退 (O(N) 搬移 + 截断)
    case none           // 不做单文件收缩 (如由分卷管理模块整卷删除)
}

public struct SpaceReclaimer: Sendable {

    /// macOS XNU 内核常量: F_PUNCHHOLE (fcntl operation 99)
    public static let F_PUNCHHOLE: Int32 = 99

    /// fpunchhole 结构体内存对齐定义
    public struct FPunchHole {
        public var fp_flags: UInt32 = 0
        public var reserved: UInt32 = 0
        public var fp_offset: off_t = 0
        public var fp_length: off_t = 0

        public init(offset: off_t, length: off_t) {
            self.fp_flags = 0
            self.reserved = 0
            self.fp_offset = offset
            self.fp_length = length
        }
    }

    /// 检测指定文件路径所在卷的文件系统策略
    public static func detectStrategy(for fileURL: URL) -> ReclaimStrategy {
        var stat = statfs()
        let path = fileURL.path
        if statfs((path as NSString).fileSystemRepresentation, &stat) == 0 {
            let fsType = withUnsafePointer(to: &stat.f_fstypename) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { cStr in
                    String(cString: cStr)
                }
            }
            if fsType.lowercased().contains("apfs") {
                return .punchHole
            }
        }
        return .shiftTruncate
    }

    /// APFS 打洞: 将 [offset, offset + length) 区间的物理块释放归还给系统
    public static func punchHole(fd: Int32, offset: off_t, length: off_t) throws {
        guard length > 0 else { return }
        var punch = FPunchHole(offset: offset, length: length)
        let result = withUnsafeMutablePointer(to: &punch) { ptr in
            fcntl(fd, F_PUNCHHOLE, ptr)
        }
        if result == -1 {
            let err = errno
            if err == ENOTSUP || err == EINVAL {
                // 如果当前卷不支持打洞，记录并不阻断主解压流
                return
            }
            throw ExtractionError.holesPunchFailed(errno: err)
        }
    }

    /// 通用回退方案: 将文件内容向前平移并截断 (对应 Python shift_then_truncate)
    public static func shiftThenTruncate(handle: FileHandle, chunkSize: Int) throws {
        let fd = handle.fileDescriptor
        var statBuf = stat()
        guard fstat(fd, &statBuf) == 0 else { return }
        let currentSize = statBuf.st_size
        guard currentSize > off_t(chunkSize) else {
            // 文件已小于等于块大小，直接截断
            ftruncate(fd, 0)
            return
        }

        var readPointer: off_t = off_t(chunkSize)
        var writePointer: off_t = 0
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        while readPointer < currentSize {
            let toRead = min(chunkSize, Int(currentSize - readPointer))
            let bytesRead = pread(fd, buffer, toRead, readPointer)
            if bytesRead <= 0 { break }

            let bytesWritten = pwrite(fd, buffer, bytesRead, writePointer)
            if bytesWritten <= 0 { break }

            readPointer += off_t(bytesRead)
            writePointer += off_t(bytesWritten)
        }

        ftruncate(fd, writePointer)
    }
}
