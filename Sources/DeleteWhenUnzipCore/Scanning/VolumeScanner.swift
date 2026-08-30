import Foundation

public struct VolumeScanner: Sendable {

    /// 提取基础名称（去除各种分卷后缀和常见压缩包扩展名）
    public static func extractBaseName(from filename: String) -> String {
        var base = filename
        let patterns: [String] = [
            #"(.*)\.part\d+\.rar$"#,
            #"(.*)\.part\d+$"#,
            #"(.*)\.zip\.\d+$"#,
            #"(.*)\.zip\.z\d+$"#,
            #"(.*)\.rar\.\d+$"#,
            #"(.*)\.rar\.part\d+$"#,
            #"(.*)\.7z\.\d+$"#,
            #"(.*)\.tar\.gz$"#,
            #"(.*)\.z\d+$"#,
            #"(.*)\.r\d+$"#,
            #"(.*)\.zip$"#,
            #"(.*)\.rar$"#,
            #"(.*)\.7z$"#,
            #"(.*)\.tar$"#,
            #"(.*)\.gz$"#,
            #"(.*)\.\d{3,}$"#
        ]

        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let range = NSRange(base.startIndex..., in: base)
                if let match = regex.firstMatch(in: base, options: [], range: range) {
                    if let captureRange = Range(match.range(at: 1), in: base) {
                        base = String(base[captureRange])
                        break
                    }
                }
            }
        }
        return base
    }

    /// 根据给定的主分卷文件，扫描所在目录下的所有关联分卷并进行精确排序。
    /// 仅回收与主卷同族 (同一分卷格式) 的文件，避免同目录下其他格式分卷被误删。
    public static func scanVolumes(mainVolumeURL: URL) -> [URL] {
        let parentDir = mainVolumeURL.deletingLastPathComponent()
        let filename = mainVolumeURL.lastPathComponent
        let baseName = extractBaseName(from: filename)

        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: parentDir.path) else {
            return [mainVolumeURL]
        }

        let escapedBase = NSRegularExpression.escapedPattern(for: baseName)
        func matches(_ item: String, _ pattern: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
            return regex.firstMatch(in: item, options: [], range: NSRange(item.startIndex..., in: item)) != nil
        }
        func mainMatches(_ suffixPattern: String) -> Bool {
            matches(filename, "^" + escapedBase + suffixPattern)
        }

        // 按主卷后缀判定分卷家族 (z01/r01 家族的首卷为 .zNN/.rNN、末卷为 .zip/.rar)
        let familyPatterns: [String]
        var isBareNumericFamily = false
        if mainMatches(#"\.part\d+\.rar$"#) {
            familyPatterns = [escapedBase + #"\.part\d+\.rar$"#]
        } else if mainMatches(#"\.zip\.\d+$"#) {
            familyPatterns = [escapedBase + #"\.zip\.\d+$"#]
        } else if mainMatches(#"\.rar\.\d+$"#) {
            familyPatterns = [escapedBase + #"\.rar\.\d+$"#]
        } else if mainMatches(#"\.7z\.\d+$"#) {
            familyPatterns = [escapedBase + #"\.7z\.\d+$"#]
        } else if mainMatches(#"\.z\d+$"#) {
            familyPatterns = [escapedBase + #"\.z\d+$"#, escapedBase + #"\.zip$"#]
        } else if mainMatches(#"\.r\d+$"#) {
            familyPatterns = [escapedBase + #"\.r\d+$"#, escapedBase + #"\.rar$"#]
        } else if mainMatches(#"\.rar$"#) {
            familyPatterns = [escapedBase + #"\.rar$"#, escapedBase + #"\.r\d+$"#]
        } else if mainMatches(#"\.zip$"#) {
            familyPatterns = [escapedBase + #"\.zip$"#, escapedBase + #"\.z\d+$"#]
        } else if mainMatches(#"\.\d{3,}$"#) {
            familyPatterns = [escapedBase + #"\.\d{3,}$"#]
            isBareNumericFamily = true
        } else {
            familyPatterns = ["^" + NSRegularExpression.escapedPattern(for: filename) + "$"]
        }
        let anchoredPatterns = familyPatterns.map { "^" + $0 }

        var matchedFiles: [String] = []
        for item in items {
            for pat in anchoredPatterns {
                if matches(item, pat) {
                    matchedFiles.append(item)
                    break
                }
            }
        }

        if matchedFiles.isEmpty {
            return [mainVolumeURL]
        }

        // 纯数字分卷 (game.001) 语义最模糊，仅当编号从 1 起连续时才视为同一套分卷，
        // 避免把同名无关文件当成成员连带删除
        if isBareNumericFamily {
            func numericSuffix(_ name: String) -> Int? {
                guard let range = name.range(of: #"\.(\d{3,})$"#, options: .regularExpression) else { return nil }
                let digits = name[range].drop(while: { !$0.isNumber })
                return Int(digits)
            }
            let numbers = matchedFiles.compactMap(numericSuffix).sorted()
            if numbers.count != matchedFiles.count || numbers.first != 1
                || zip(numbers, numbers.dropFirst()).contains(where: { $1 - $0 != 1 }) {
                return [mainVolumeURL]
            }
        }

        // 排序: zNN/rNN 家族中 .zip/.rar 末卷排在最后，其余按自然数字序
        let hasZVolumes = matchedFiles.contains { $0.range(of: #"\.z\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let hasRVolumes = matchedFiles.contains { $0.range(of: #"\.r\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let lastVolumePattern = hasZVolumes ? #"\.zip$"# : (hasRVolumes ? #"\.rar$"# : nil)

        matchedFiles.sort { (a, b) -> Bool in
            if let lastPattern = lastVolumePattern {
                let aIsLast = a.range(of: lastPattern, options: [.regularExpression, .caseInsensitive]) != nil
                let bIsLast = b.range(of: lastPattern, options: [.regularExpression, .caseInsensitive]) != nil
                if aIsLast != bIsLast {
                    return !aIsLast // 末卷排在最后
                }
            }
            return a.localizedStandardCompare(b) == .orderedAscending
        }

        return matchedFiles.map { parentDir.appendingPathComponent($0) }
    }
}
