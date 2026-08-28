import Foundation
import DeleteWhenUnzipCore

@main
struct DeleteWhenUnzipCLI {

    static let version = "0.1.3"

    static func printUsage() {
        print("""
        ========================================================
         dwum - DeleteWhenUnzipMac (macOS Native Swift CLI)
         边解压边删除 —— APFS 物理打洞零额外写入 & 分卷即时销毁
        ========================================================
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
            printUsage()
            exit(1)
        }

        let firstArg = args[1]

        switch firstArg {
        case "-h", "--help", "help":
            printUsage()
            exit(0)

        case "-v", "--version", "version":
            print("dwum version \(version) (macOS pure Swift native)")
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
            switch info.type {
            case .single:
                let reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes)
                let extractor = LibArchiveExtractor()
                try await extractor.extract(
                    source: reader,
                    to: info.outputDirectoryURL,
                    password: password
                ) { progress in
                    renderProgress(progress: progress)
                }

            case .multiVolume(let format):
                if format == .rar && UnRARProcess.findUnRAR() != nil {
                    let unrar = UnRARProcess()
                    try await unrar.extractAndDelete(
                        mainVolume: info.mainVolumeURL,
                        volumes: info.volumeURLs,
                        outputDirectory: info.outputDirectoryURL,
                        password: password
                    ) { progress in
                        renderProgress(progress: progress)
                    }
                } else {
                    let chainReader = try VolumeChainReader(volumes: info.volumeURLs, chunkSize: chunkSizeBytes)
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

    private static func renderProgress(progress: ExtractionProgress) {
        let percent = Int(progress.progress * 100)
        let barLength = 30
        let filled = Int(Double(barLength) * progress.progress)
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, barLength - filled))
        let processedStr = DiskSpaceMonitor.formatBytes(progress.processedBytes)
        let totalStr = DiskSpaceMonitor.formatBytes(progress.totalBytes)

        let line = String(format: "\r[%@] %3d%% | %@ / %@ | %@", bar, percent, processedStr, totalStr, progress.currentFileName)
        let truncatedLine = line.count > 100 ? String(line.prefix(97)) + "..." : line
        FileHandle.standardOutput.write(truncatedLine.data(using: .utf8)!)
    }

    private static func performUpdate() async {
        print("🔄 正在检查 dwum 最新版本...")
        let resolvedPath = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        let isHomebrewInstalled = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/dwum") ||
                                  FileManager.default.fileExists(atPath: "/usr/local/bin/dwum") ||
                                  resolvedPath.contains("Cellar") ||
                                  resolvedPath.contains("/opt/homebrew") ||
                                  resolvedPath.contains("/usr/local")

        if isHomebrewInstalled {
            print("🍺 检测到当前通过 Homebrew 安装，正在通过 Homebrew 执行升级...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["brew", "upgrade", "dwum"]
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    print("\n✨ dwum 已成功升级至最新版本！")
                } else {
                    print("\nℹ️ 提示: 若未检测到更新，可先运行 'brew update' 后再试。")
                }
            } catch {
                print("❌ 启动 Homebrew 失败: \(error.localizedDescription)")
            }
            return
        }

        // 独立二进制安装下的更新检查
        guard let url = URL(string: "https://api.github.com/repos/luanyufei/delete_when_unzip_mac/releases") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("dwum-updater", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ 获取版本信息失败，请检查网络连接。")
                return
            }

            if let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstRelease = releases.first,
               let tagName = firstRelease["tag_name"] as? String {
                let latestVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if latestVersion == version {
                    print("✨ 当前已是最新版本 (v\(version))，无需更新。")
                } else {
                    print("🚀 发现新版本: v\(latestVersion)（当前版本: v\(version)）")
                    print("👉 请运行 'brew upgrade dwum' 或访问 https://github.com/luanyufei/delete_when_unzip_mac/releases 获取最新版。")
                }
            } else {
                print("✨ 当前已是最新版本 (v\(version))。")
            }
        } catch {
            print("❌ 检查更新时出错: \(error.localizedDescription)")
        }
    }
}
