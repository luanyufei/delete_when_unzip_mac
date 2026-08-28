import Foundation
import DeleteWhenUnzipCore

@main
struct DeleteWhenUnzipCLI {

    static func printUsage() {
        print("""
        ========================================================
         dwum - DeleteWhenUnzipMac (macOS Native Swift CLI)
         边解压边删除 —— APFS 物理打洞零额外写入 & 分卷即时销毁
        ========================================================
        用法:
          dwum <压缩文件路径> [块大小(MB)] [密码]

        示例:
          dwum game.zip
          dwum game.part1.rar 10 mypassword
          dwum archive.z01 50

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

        let inputPath = args[1]
        if inputPath == "-h" || inputPath == "--help" {
            printUsage()
            exit(0)
        }

        let fileURL = URL(fileURLWithPath: inputPath)
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
        // 限制单行长度防止溢出
        let truncatedLine = line.count > 100 ? String(line.prefix(97)) + "..." : line
        FileHandle.standardOutput.write(truncatedLine.data(using: .utf8)!)
    }
}
