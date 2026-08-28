import Foundation

public struct DiskSpaceMonitor: Sendable {

    /// 查询指定路径所在磁盘卷的可用空间字节数
    public static func availableDiskSpace(at url: URL) -> UInt64 {
        var targetURL = url
        if !FileManager.default.fileExists(atPath: targetURL.path) {
            targetURL = targetURL.deletingLastPathComponent()
        }

        do {
            let values = try targetURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
                return UInt64(important)
            }
            if let available = values.volumeAvailableCapacity, available > 0 {
                return UInt64(available)
            }
        } catch {}

        var stat = statfs()
        let path = targetURL.path
        if statfs((path as NSString).fileSystemRepresentation, &stat) == 0 {
            return UInt64(stat.f_bavail) * UInt64(stat.f_bsize)
        }
        return 0
    }

    /// 格式化字节数
    public static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
