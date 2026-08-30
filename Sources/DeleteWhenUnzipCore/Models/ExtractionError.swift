import Foundation

public enum ExtractionError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case unreadableFile(URL)
    case unsupportedFormat(String)
    case invalidVolumeSequence(String)
    case holesPunchFailed(errno: Int32)
    case archiveOpenFailed(String)
    case readDataFailed(String)
    case writeDataFailed(String)
    case unrarNotFound
    case unrarFailed(exitCode: Int32, message: String)
    case passwordRequired
    case wrongPassword
    case encryptedDecoderUnsupported(formatName: String)
    case extractionCancelled
    case insufficientDiskSpace(requiredBytes: UInt64, availableBytes: UInt64)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "文件不存在: \(url.path)"
        case .unreadableFile(let url):
            return "无法读取文件: \(url.path)"
        case .unsupportedFormat(let reason):
            return "不支持的文件格式: \(reason)"
        case .invalidVolumeSequence(let reason):
            return "分卷序列错误: \(reason)"
        case .holesPunchFailed(let errno):
            return "APFS 打洞释放空间失败 (errno: \(errno))"
        case .archiveOpenFailed(let reason):
            return "打开压缩包失败: \(reason)"
        case .readDataFailed(let reason):
            return "读取压缩数据失败: \(reason)"
        case .writeDataFailed(let reason):
            return "写入解压文件失败: \(reason)"
        case .unrarNotFound:
            return "未找到 unrar 命令行工具。请安装 Homebrew unrar (`brew install --cask rar`) 或在设置中配置。"
        case .unrarFailed(let code, let msg):
            return "UnRAR 解压进程异常退出 (退出码: \(code)): \(msg)"
        case .passwordRequired:
            return "该压缩文件已加密，需要提供解压密码。"
        case .wrongPassword:
            return "解压密码错误。"
        case .encryptedDecoderUnsupported(let formatName):
            return "该压缩包的加密格式（\(formatName)）超出 libarchive 解码能力，暂无法解密。RAR 加密包可安装 unrar 后重试: brew install --cask rar"
        case .extractionCancelled:
            return "解压任务已被用户中止。"
        case .insufficientDiskSpace(let req, let avail):
            let reqMB = Double(req) / (1024 * 1024)
            let availMB = Double(avail) / (1024 * 1024)
            return String(format: "磁盘剩余空间严重不足（需 %.1f MB，仅剩 %.1f MB）", reqMB, availMB)
        case .unknown(let msg):
            return "未知错误: \(msg)"
        }
    }
}
