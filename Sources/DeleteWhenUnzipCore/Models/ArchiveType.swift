import Foundation

public enum ArchiveFormat: String, Sendable, CaseIterable {
    case zip = "ZIP"
    case rar = "RAR"
    case tar = "TAR"
    case tarGz = "TAR.GZ"
    case sevenZip = "7-Zip"
    case other = "Other"
}

public enum ArchiveType: Sendable, Equatable {
    case single(format: ArchiveFormat)
    case multiVolume(format: ArchiveFormat)

    public var isMultiVolume: Bool {
        switch self {
        case .single: return false
        case .multiVolume: return true
        }
    }

    public var format: ArchiveFormat {
        switch self {
        case .single(let f): return f
        case .multiVolume(let f): return f
        }
    }

    public var displayName: String {
        switch self {
        case .single(let f):
            return "单文件 \(f.rawValue)"
        case .multiVolume(let f):
            return "多分卷 \(f.rawValue)"
        }
    }
}
