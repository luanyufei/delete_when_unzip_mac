import Foundation

public final class UnRARProcess: Sendable {

    public init() {}

    /// 探测可用的 unrar 可执行文件路径
    public static func findUnRAR() -> URL? {
        // 1. App Bundle 内部预置
        if let bundled = Bundle.main.url(forResource: "unrar", withExtension: nil) {
            return bundled
        }
        if let appResource = Bundle.main.resourceURL?.appendingPathComponent("unrar"),
           FileManager.default.isExecutableFile(atPath: appResource.path) {
            return appResource
        }

        // 2. 常见系统与 Homebrew 路径
        let candidatePaths = [
            "/opt/homebrew/bin/unrar",      // Apple Silicon Homebrew
            "/usr/local/bin/unrar",         // Intel Homebrew
            "/opt/homebrew/bin/unar",       // Apple Silicon unar
            "/usr/local/bin/unar",          // Intel unar
            "/usr/bin/unrar"
        ]

        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    /// 执行 unrar 子进程并实时监控 stdout 以实现逐卷删除
    public func extractAndDelete(
        mainVolume: URL,
        volumes: [URL],
        outputDirectory: URL,
        password: String?,
        progressHandler: @escaping @Sendable (ExtractionProgress) -> Void
    ) async throws {
        guard let unrarURL = Self.findUnRAR() else {
            throw ExtractionError.unrarNotFound
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let isUnar = unrarURL.lastPathComponent.lowercased() == "unar"

        var pendingVolumes = volumes
        let totalCount = Double(volumes.count)
        var totalBytes: UInt64 = 0
        for v in volumes {
            if let attrs = try? fileManager.attributesOfItem(atPath: v.path),
               let sz = attrs[.size] as? UInt64 {
                totalBytes += sz
            }
        }

        let process = Process()
        process.executableURL = unrarURL

        var arguments: [String] = []
        if isUnar {
            arguments = ["-o", outputDirectory.path, "-f"]
            if let pwd = password, !pwd.isEmpty {
                arguments.append(contentsOf: ["-p", pwd])
            }
            arguments.append(mainVolume.path)
        } else {
            // 标准 unrar 命令: unrar x -o+ [-ppassword] archive output/
            arguments = ["x", "-o+"]
            if let pwd = password, !pwd.isEmpty {
                arguments.append("-p\(pwd)")
            }
            arguments.append(mainVolume.path)
            arguments.append(outputDirectory.path + "/")
        }
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let pipeHandle = pipe.fileHandleForReading
        var outputAccumulator = ""

        // 异步流式读取子进程输出
        for try await line in pipeHandle.bytes.lines {
            try Task.checkCancellation()
            outputAccumulator += line + "\n"

            if line.contains("Extracting from") || line.contains("Extracting ") {
                // 等待 1 秒确保上一卷已被 unrar 读取完毕
                try? await Task.sleep(for: .seconds(1))
                if pendingVolumes.count > 1 {
                    let volumeToDelete = pendingVolumes.removeFirst()
                    try? fileManager.removeItem(at: volumeToDelete)

                    let remainingCount = Double(pendingVolumes.count)
                    let progressFraction = min(0.99, 1.0 - (remainingCount / totalCount))
                    progressHandler(ExtractionProgress(
                        progress: progressFraction,
                        currentFileName: volumeToDelete.lastPathComponent,
                        processedBytes: UInt64(Double(totalBytes) * progressFraction),
                        totalBytes: totalBytes
                    ))
                }
            } else if line.contains("All OK") || line.contains("Successfully extracted") {
                // 解压顺利结束，删除最后一卷
                if let lastVolume = pendingVolumes.first {
                    try? fileManager.removeItem(at: lastVolume)
                    pendingVolumes.removeAll()
                }
                progressHandler(ExtractionProgress(
                    progress: 1.0,
                    currentFileName: "完成",
                    processedBytes: totalBytes,
                    totalBytes: totalBytes
                ))
            }
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            if outputAccumulator.contains("password") || outputAccumulator.contains("Password") {
                throw ExtractionError.wrongPassword
            }
            throw ExtractionError.unrarFailed(exitCode: process.terminationStatus, message: outputAccumulator)
        }

        // 兜底清理剩余卷
        for v in pendingVolumes {
            try? fileManager.removeItem(at: v)
        }
    }
}
