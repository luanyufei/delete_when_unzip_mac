import CryptoKit
import Foundation
import DeleteWhenUnzipCore

@main
struct DeleteWhenUnzipCLI {

    static let version = "0.2.0"
    static let repoBase = "https://github.com/luanyufei/delete_when_unzip_mac"
    static let repoAPIBase = "https://api.github.com/repos/luanyufei/delete_when_unzip_mac"

    static let banner =
        """
        ========================================================
         dwum - DeleteWhenUnzipMac
         边解压边删除 —— Streaming unzip with real-time space reclaim
        ========================================================
        """

    static func printShortIntro() {
        print("""
        \(banner)

        用法: dwum <压缩包路径> [块大小(MB)] [密码]
              dwum update            检查并更新到最新版本

        详细说明请运行: dwum --help
        """)
    }

    static func printUsage() {
        print("""
        \(banner)

        用法:
          dwum <压缩文件路径> [块大小(MB)] [密码]
          dwum update               检查并自动更新到最新版本
          dwum --version | -v       查看当前版本信息
          dwum --help | -h          查看帮助说明

        示例:
          dwum game.zip
          dwum game.part1.rar 10 mypassword
          dwum archive.z01 50
          dwum update

        参数说明:
          <压缩文件路径>  主压缩包或首个分卷路径 (.zip, .rar, .part1.rar, .z01 等)
          [块大小(MB)]    单次处理缓冲区大小（默认: 10 MB）
          [密码]          压缩包密码（可选）
        """)
    }

    static func main() async {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            printShortIntro()
            exit(1)
        }

        let firstArg = args[1]

        switch firstArg {
        case "-h", "--help", "help":
            printUsage()
            exit(0)

        case "-v", "--version", "version":
            print("dwum v\(version) (Apple Silicon)")
            exit(0)

        case "update", "upgrade":
            await performUpdate()
            exit(0)

        default:
            break
        }

        let fileURL = URL(fileURLWithPath: firstArg)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("❌ 错误: 文件不存在 -> \(fileURL.path)")
            exit(1)
        }

        var chunkSizeMB = 10
        if args.count >= 3, let mb = Int(args[2]), mb > 0 {
            chunkSizeMB = mb
        }

        var password: String? = nil
        if args.count >= 4 {
            password = args[3]
        }

        print("🔍 正在扫描并分析压缩包: \(fileURL.lastPathComponent)")

        let info: ArchiveInfo
        do {
            info = try ArchiveDetector.detect(mainFileURL: fileURL)
        } catch {
            print("❌ 格式检测失败: \(error.localizedDescription)")
            exit(1)
        }
        guard info.type.format != .other else {
            print("❌ 无法识别的压缩格式。支持 ZIP / RAR / 7Z / TAR / GZIP 及常见分卷。")
            exit(1)
        }

        // 加密预探测: 只读检查，避免破坏性解压开始后才发现需要密码（届时源文件已被打洞破坏）
        var preferUnrar = false
        let probeResult = LibArchiveExtractor.probeEncryption(volumeURLs: info.volumeURLs, password: password)
        switch probeResult {
        case .passwordRequired where password == nil:
            print("🔒 该压缩包已加密。")
            guard let input = promptPassword("请输入解压密码:"), !input.isEmpty else {
                print("❌ 未输入密码，已取消。")
                exit(1)
            }
            password = input
        case .decoderUnsupported:
            if info.type.format == .rar {
                guard UnRARProcess.findUnRAR() != nil else {
                    print("❌ 该压缩包使用 libarchive 不支持的 RAR5 加密格式。")
                    print("   请先安装 unrar: brew install --cask rar")
                    exit(1)
                }
                preferUnrar = true
                if password == nil {
                    print("🔒 该压缩包已加密（通过 unrar 解密）。")
                    guard let input = promptPassword("请输入解压密码:"), !input.isEmpty else {
                        print("❌ 未输入密码，已取消。")
                        exit(1)
                    }
                    password = input
                }
            } else {
                print("❌ \(ExtractionError.encryptedDecoderUnsupported(formatName: info.type.format.rawValue).localizedDescription)")
                exit(1)
            }
        case .unknown where info.type.format == .rar && UnRARProcess.findUnRAR() != nil:
            // libarchive 对该 RAR 无把握 (罕见压缩方法等)，交给能力更完整的 unrar
            preferUnrar = true
        default:
            break
        }

        print("📦 识别格式: \(info.type.displayName)")
        print("📁 目标解压目录: \(info.outputDirectoryURL.path)")
        print("💾 压缩包总大小: \(info.formattedTotalSize)")
        if info.volumeURLs.count > 1 {
            print("📚 关联分卷数量: \(info.volumeURLs.count) 卷")
            for (idx, vol) in info.volumeURLs.enumerated() {
                print("   [\(idx + 1)] \(vol.lastPathComponent)")
            }
        }

        let available = DiskSpaceMonitor.availableDiskSpace(at: fileURL)
        print("💽 当前磁盘可用空间: \(DiskSpaceMonitor.formatBytes(available))")
        print("⚙️  块大小: \(chunkSizeMB) MB")
        print("--------------------------------------------------------")
        print("⚠️  警告: 本操作具有破坏性，解压过程中原压缩包将被物理销毁！")
        print("🚀 开始解压与空间实时回收...")
        print("--------------------------------------------------------")

        let startTime = Date()
        let chunkSizeBytes = chunkSizeMB * 1024 * 1024

        do {
            let unrarAvailable = UnRARProcess.findUnRAR() != nil

            func runUnrar(volumes: [URL]) async throws {
                let unrar = UnRARProcess()
                try await unrar.extractAndDelete(
                    mainVolume: info.mainVolumeURL,
                    volumes: volumes,
                    outputDirectory: info.outputDirectoryURL,
                    password: password
                ) { progress in
                    renderProgress(progress: progress)
                }
            }

            switch info.type {
            case .single(let format):
                if format == .rar && preferUnrar {
                    try await runUnrar(volumes: [info.mainVolumeURL])
                } else {
                    let reader: ChunkReader
                    if format == .sevenZip {
                        // 7z 头信息位于尾部需要随机访问: APFS 上延迟到头部解析完成后打洞，
                        // 兼顾空间回收与随机读；非 APFS 无打洞可用，退回整体删除模式
                        if SpaceReclaimer.detectStrategy(for: info.mainVolumeURL) == .punchHole {
                            reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes,
                                                     strategy: .punchHole, punchAfterSeek: true)
                        } else {
                            reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes,
                                                     strategy: ReclaimStrategy.none)
                        }
                    } else {
                        reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes)
                    }
                    let extractor = LibArchiveExtractor()
                    try await extractor.extract(
                        source: reader,
                        to: info.outputDirectoryURL,
                        password: password
                    ) { progress in
                        renderProgress(progress: progress)
                    }
                }

            case .multiVolume(let format):
                if format == .rar && (preferUnrar || unrarAvailable) {
                    try await runUnrar(volumes: info.volumeURLs)
                } else {
                    let chainReader = try VolumeChainReader(
                        volumes: info.volumeURLs,
                        chunkSize: chunkSizeBytes,
                        deletesVolumesAsRead: format != .sevenZip
                    )
                    let extractor = LibArchiveExtractor()
                    try await extractor.extract(
                        source: chainReader,
                        to: info.outputDirectoryURL,
                        password: password
                    ) { progress in
                        renderProgress(progress: progress)
                    }
                }
            }

            let elapsed = Date().timeIntervalSince(startTime)
            print("\n\n🎉 解压完成！总耗时: \(String(format: "%.1f", elapsed)) 秒")
            let endAvailable = DiskSpaceMonitor.availableDiskSpace(at: fileURL)
            print("💽 释放后磁盘可用空间: \(DiskSpaceMonitor.formatBytes(endAvailable))")
            print("📁 解压文件已保存至: \(info.outputDirectoryURL.path)")

        } catch {
            print("\n\n❌ 解压失败: \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - Update

    private static func performUpdate() async {
        print("🔄 正在检查 dwum 最新版本...")

        guard let latest = await fetchLatestRelease() else {
            print("❌ 获取版本信息失败，请检查网络连接后重试。")
            return
        }

        guard isNewerVersion(latest.version, than: version) else {
            print("✨ 当前已是最新版本 (v\(version))，无需更新。")
            return
        }

        print("🚀 发现新版本: v\(latest.version)（当前版本: v\(version)）")

        guard confirm("是否立即升级到 v\(latest.version)? [y/n]") else {
            print("已取消更新。可稍后手动前往 https://github.com/luanyufei/delete_when_unzip_mac/releases")
            return
        }

        let resolvedPath = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        // 仅当自身二进制位于 Homebrew Cellar 内才视为 brew 安装，
        // 避免同机存在 brew 版 dwum 时误判独立安装的二进制
        let isHomebrewInstalled = resolvedPath.contains("/Cellar/")

        if isHomebrewInstalled {
            await upgradeViaHomebrew()
        } else {
            await selfUpdate(assetURL: latest.assetURL, newVersion: latest.version)
        }
    }

    private static func fetchLatestRelease() async -> (version: String, assetURL: String?)? {
        // 优先走 API；遭遇 403 匿名限额等故障时回退到 releases 页面重定向解析
        if let result = await fetchLatestViaAPI() { return result }
        return await fetchLatestViaRedirect()
    }

    private static func fetchLatestViaAPI() async -> (version: String, assetURL: String?)? {
        guard let url = URL(string: "\(repoAPIBase)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("dwum-updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                return nil
            }
            var assetURL: String? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                assetURL = assets.first { asset in
                    (asset["name"] as? String)?.hasSuffix("-macos.tar.gz") == true
                }?["browser_download_url"] as? String
            }
            return (tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), assetURL)
        } catch {
            return nil
        }
    }

    /// github.com 的 /releases/latest 页面会 302 到 /releases/tag/vX.Y.Z，
    /// 从最终 URL 即可取得最新正式版本号，不受 GitHub API 匿名限额影响。
    private static func fetchLatestViaRedirect() async -> (version: String, assetURL: String?)? {
        guard let url = URL(string: "https://github.com/luanyufei/delete_when_unzip_mac/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("dwum-updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let finalURL = httpResponse.url else {
                return nil
            }
            let components = finalURL.pathComponents
            guard let tagIndex = components.firstIndex(of: "tag"), tagIndex + 1 < components.count else {
                return nil
            }
            let tag = components[tagIndex + 1]
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let assetURL = "\(repoBase)/releases/download/\(tag)/dwum-\(tag)-macos.tar.gz"
            return (version, assetURL)
        } catch {
            return nil
        }
    }

    /// 语义化版本比较: 逐段按整数比较，位数不足补 0（0.1.9 < 0.1.10）
    private static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let a = versionComponents(candidate)
        let b = versionComponents(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func versionComponents(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }

    private static func confirm(_ question: String) -> Bool {
        print("\(question) ", terminator: "")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), input == "y" || input == "yes" else {
            return false
        }
        return true
    }

    /// 终端交互时关闭回显读取密码；管道等非交互场景直接读取一行
    private static func promptPassword(_ prompt: String) -> String? {
        print("\(prompt) ", terminator: "")
        let original = isInteractiveTTY() ? disableEcho() : nil
        defer {
            if let original { restoreEcho(original) }
            if isInteractiveTTY() { print("") }
        }
        guard let line = readLine() else { return nil }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isInteractiveTTY() -> Bool {
        isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    private static func disableEcho() -> termios {
        var state = termios()
        tcgetattr(STDIN_FILENO, &state)
        var noEcho = state
        noEcho.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &noEcho)
        return state
    }

    private static func restoreEcho(_ state: termios) {
        var restored = state
        tcsetattr(STDIN_FILENO, TCSANOW, &restored)
    }

    private static func upgradeViaHomebrew() async {
        print("🍺 检测到当前通过 Homebrew 安装，正在执行 brew upgrade...")
        let status = await runProcess("/usr/bin/env", ["brew", "upgrade", "dwum"],
                                      environment: ["HOMEBREW_NO_ASK": "1"],
                                      stdin: .nullDevice)
        guard status == 0 else {
            print("\n❌ Homebrew 升级失败（退出码 \(status)）。可尝试先运行 'brew update' 再重试。")
            return
        }
        var installed = await captureProcess("/opt/homebrew/bin/brew", ["list", "--versions", "dwum"])
        if installed == nil {
            installed = await captureProcess("/usr/local/bin/brew", ["list", "--versions", "dwum"])
        }
        let upgradedVersion = (installed ?? "").split(separator: " ").last.map(String.init) ?? ""
        if !upgradedVersion.isEmpty && upgradedVersion != version {
            print("\n✨ 升级完成！当前已安装: dwum \(upgradedVersion)")
            print("ℹ️ 重新运行 'dwum' 即可使用新版本。")
        } else {
            print("\n⚠️ 升级命令已执行，但版本未发生变化 (仍是 v\(version))，请检查 Homebrew 源配置。")
        }
    }

    /// 独立二进制安装: 下载 release 资源包并原子替换自身
    private static func selfUpdate(assetURL: String?, newVersion: String) async {
        guard let assetURL, let downloadURL = URL(string: assetURL) else {
            print("❌ 最新版本未提供 macOS 二进制资源包，请前往 https://github.com/luanyufei/delete_when_unzip_mac/releases 手动下载。")
            return
        }

        print("⬇️  正在下载 dwum v\(newVersion)...")
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("dwum-update-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let (archiveURL, response) = try await URLSession.shared.download(from: downloadURL)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("❌ 下载失败 (HTTP \(httpResponse.statusCode))。")
                try? fm.removeItem(at: tmpDir)
                return
            }

            // 校验和验证: 发布资产附带 .sha256 sidecar，存在则强制比对
            if let expected = await fetchSidecarChecksum(downloadURL) {
                let actual = try sha256Hex(of: archiveURL)
                guard actual == expected else {
                    print("❌ 校验和不匹配，已中止更新 (期望 \(expected.prefix(16))…, 实际 \(actual.prefix(16))…)。")
                    try? fm.removeItem(at: tmpDir)
                    return
                }
                print("🔐 SHA-256 校验通过。")
            } else {
                print("⚠️ 该版本未提供校验和文件，跳过完整性校验。")
            }

            print("📦 正在解压并校验...")
            let extractStatus = await runProcess("/usr/bin/tar", ["-xzf", archiveURL.path, "-C", tmpDir.path])
            try? fm.removeItem(at: archiveURL)
            guard extractStatus == 0 else {
                print("❌ 解压下载的资源包失败。")
                try? fm.removeItem(at: tmpDir)
                return
            }

            let newBinaryURL = tmpDir.appendingPathComponent("dwum")
            guard fm.fileExists(atPath: newBinaryURL.path) else {
                print("❌ 资源包中未找到 dwum 可执行文件。")
                try? fm.removeItem(at: tmpDir)
                return
            }

            guard let currentURL = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
                print("❌ 无法定位当前可执行文件路径。")
                try? fm.removeItem(at: tmpDir)
                return
            }

            let checkOutput = await captureProcess(newBinaryURL.path, ["--version"])
            guard checkOutput?.contains(newVersion) == true else {
                print("❌ 新版本二进制校验失败，已中止更新，原文件未改动。")
                try? fm.removeItem(at: tmpDir)
                return
            }

            let backupURL = currentURL.appendingPathExtension("old")
            try? fm.removeItem(at: backupURL)
            try fm.moveItem(at: currentURL, to: backupURL)
            do {
                try fm.moveItem(at: newBinaryURL, to: currentURL)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentURL.path)
            } catch {
                try? fm.moveItem(at: backupURL, to: currentURL)
                print("❌ 替换二进制失败，已恢复原文件: \(error.localizedDescription)")
                try? fm.removeItem(at: tmpDir)
                return
            }

            try? fm.removeItem(at: backupURL)
            try? fm.removeItem(at: tmpDir)
            print("\n✨ 更新完成！dwum 已升级至 v\(newVersion)。")
        } catch {
            print("❌ 自动更新失败: \(error.localizedDescription)")
            try? fm.removeItem(at: tmpDir)
        }
    }

    private enum ProcessStdin {
        case inherit
        case nullDevice
    }

    /// 获取发布资产对应的 .sha256 sidecar 内容 (小写十六进制)
    private static func fetchSidecarChecksum(_ assetURL: URL) async -> String? {
        guard var components = URLComponents(url: assetURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += ".sha256"
        guard let sidecarURL = components.url else { return nil }
        var request = URLRequest(url: sidecarURL)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            let text = String(data: data, encoding: .utf8) ?? ""
            // 常见格式: "<hex>  <filename>"
            guard let token = text.split(separator: "\n").first?.split(separator: " ").first else { return nil }
            let hex = String(token).lowercased()
            return hex.count == 64 && hex.allSatisfy({ $0.isHexDigit }) ? hex : nil
        } catch {
            return nil
        }
    }

    private static func sha256Hex(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 运行外部进程。stdin 默认连接 /dev/null: 子进程无法读取终端，
    /// 既避免 Homebrew 的交互确认挂起，也保证升级过程非交互可控。
    @discardableResult
    private static func runProcess(_ executablePath: String,
                                   _ arguments: [String],
                                   environment: [String: String] = [:],
                                   stdin: ProcessStdin = .nullDevice) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = (stdin == .nullDevice) ? FileHandle.nullDevice : FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            environment.forEach { env[$0.key] = $0.value }
            process.environment = env
        }
        do {
            try process.run()
        } catch {
            return -1
        }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }

    private static func captureProcess(_ executablePath: String, _ arguments: [String]) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
        }
        guard status == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Progress Rendering

    private static var lastProgressLineLength = 0

    private static func renderProgress(progress: ExtractionProgress) {
        let percent = Int(progress.progress * 100)
        let barLength = 30
        let filled = Int(Double(barLength) * progress.progress)
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, barLength - filled))
        let processedStr = DiskSpaceMonitor.formatBytes(progress.processedBytes)
        let totalStr = DiskSpaceMonitor.formatBytes(progress.totalBytes)

        var name = progress.currentFileName
        if name.count > 30 { name = String(name.prefix(27)) + "..." }
        let line = String(format: "\r[%@] %3d%% | %@ / %@ | %@", bar, percent, processedStr, totalStr, name)
        // 用空格补齐上一行残留，避免终端出现旧字符
        let padding = String(repeating: " ", count: max(0, lastProgressLineLength - line.count))
        lastProgressLineLength = max(line.count, lastProgressLineLength)
        FileHandle.standardOutput.write((line + padding).data(using: .utf8)!)
    }
}
