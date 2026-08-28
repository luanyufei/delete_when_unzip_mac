import Foundation

public struct VolumeScanner: Sendable {

    /// 提取基础名称（去除各种分卷后缀和常见压缩包扩展名）
    public static func extractBaseName(from filename: String) -> String {
        var base = filename
        let patterns: [String] = [
            #"(.*)\.part\d+\.rar$"#,
            #"(.*)\.part\d+$"#,
            #"(.*)\.z\d+$"#,
            #"(.*)\.r\d+$"#,
            #"(.*)\.zip$"#,
            #"(.*)\.rar$"#,
            #"(.*)\.7z\.\d+$"#,
            #"(.*)\.7z$"#,
            #"(.*)\.tar\.gz$"#,
            #"(.*)\.tar$"#,
            #"(.*)\.gz$"#,
            #"(.*)\.zip\.\d+$"#,
            #"(.*)\.zip\.z\d+$"#,
            #"(.*)\.rar\.\d+$"#,
            #"(.*)\.rar\.part\d+$"#,
            #"(.*)\.\d+$"#
        ]

        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let range = NSRange(base.startIndex..., in: base)
                if let match = regex.firstMatch(in: base, options: [], range: range) {
                    if let captureRange = Range(match.range(at: 1), in: base) {
                        base = String(base[captureRange])
                    }
                }
            }
        }
        return base
    }

    /// 根据给定的主分卷文件，扫描所在目录下的所有关联分卷并进行精确排序
    public static func scanVolumes(mainVolumeURL: URL) -> [URL] {
        let parentDir = mainVolumeURL.deletingLastPathComponent()
        let filename = mainVolumeURL.lastPathComponent
        let baseName = extractBaseName(from: filename)

        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: parentDir.path) else {
            return [mainVolumeURL]
        }

        let escapedBase = NSRegularExpression.escapedPattern(for: baseName)
        let volumeRegexPatterns = [
            #"^"# + escapedBase + #"\.z\d+$"#,
            #"^"# + escapedBase + #"\.zip$"#,
            #"^"# + escapedBase + #"\.zip\.\d+$"#,
            #"^"# + escapedBase + #"\.r\d+$"#,
            #"^"# + escapedBase + #"\.rar$"#,
            #"^"# + escapedBase + #"\.rar\.\d+$"#,
            #"^"# + escapedBase + #"\.part\d+\.rar$"#,
            #"^"# + escapedBase + #"\.7z\.\d+$"#,
            #"^"# + escapedBase + #"\.\d{3,}$"#
        ]

        var matchedFiles: [String] = []
        for item in items {
            let itemRange = NSRange(item.startIndex..., in: item)
            for pat in volumeRegexPatterns {
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                   regex.firstMatch(in: item, options: [], range: itemRange) != nil {
                    matchedFiles.append(item)
                    break
                }
            }
        }

        if matchedFiles.isEmpty {
            return [mainVolumeURL]
        }

        // 对匹配到的分卷进行排序
        // 针对 .z01, .z02, ... .zip 规则：.z01 先排，.zip 放在最后
        let hasZVolumes = matchedFiles.contains { $0.range(of: #"\.z\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let hasZipMain = matchedFiles.contains { $0.range(of: #"\.zip$"#, options: [.regularExpression, .caseInsensitive]) != nil }

        matchedFiles.sort { (a, b) -> Bool in
            if hasZVolumes && hasZipMain {
                let aIsZip = a.range(of: #"\.zip$"#, options: [.regularExpression, .caseInsensitive]) != nil
                let bIsZip = b.range(of: #"\.zip$"#, options: [.regularExpression, .caseInsensitive]) != nil
                if aIsZip != bIsZip {
                    return !aIsZip // .zip 排在最后
                }
            }
            return a.localizedStandardCompare(b) == .orderedAscending
        }

        return matchedFiles.map { parentDir.appendingPathComponent($0) }
    }
}
