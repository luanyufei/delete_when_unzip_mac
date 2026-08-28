import Foundation

public struct ArchiveDetector: Sendable {

    /// 检测指定文件的压缩格式与单/多分卷属性
    public static func detect(mainFileURL: URL) throws -> ArchiveInfo {
        guard FileManager.default.fileExists(atPath: mainFileURL.path) else {
            throw ExtractionError.fileNotFound(mainFileURL)
        }

        let filename = mainFileURL.lastPathComponent
        let baseName = VolumeScanner.extractBaseName(from: filename)
        let outputDir = mainFileURL.deletingLastPathComponent().appendingPathComponent(baseName)

        let volumes = VolumeScanner.scanVolumes(mainVolumeURL: mainFileURL)
        let isMulti = volumes.count > 1

        // 读取首部 8 字节魔数进行格式识别
        let format = detectFormat(fileURL: volumes.first ?? mainFileURL)
        let archiveType: ArchiveType = isMulti ? .multiVolume(format: format) : .single(format: format)

        return ArchiveInfo(
            type: archiveType,
            mainVolumeURL: mainFileURL,
            volumeURLs: volumes,
            baseName: baseName,
            outputDirectoryURL: outputDir
        )
    }

    private static func detectFormat(fileURL: URL) -> ArchiveFormat {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return formatFromExtension(fileURL.pathExtension)
        }
        defer { try? handle.close() }

        let magic = handle.readData(ofLength: 8)
        if magic.count >= 2 && magic.starts(with: [0x50, 0x4B]) {
            return .zip
        } else if magic.count >= 4 && magic.starts(with: [0x52, 0x61, 0x72, 0x21]) {
            return .rar
        } else if magic.count >= 2 && magic.starts(with: [0x1F, 0x8B]) {
            return .tarGz
        } else if magic.count >= 6 && magic.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
            return .sevenZip
        }

        return formatFromExtension(fileURL.pathExtension)
    }

    private static func formatFromExtension(_ ext: String) -> ArchiveFormat {
        let lower = ext.lowercased()
        switch lower {
        case "zip", "z01", "z02":
            return .zip
        case "rar", "r01", "r02":
            return .rar
        case "gz", "tgz":
            return .tarGz
        case "tar":
            return .tar
        case "7z":
            return .sevenZip
        default:
            return .other
        }
    }
}
