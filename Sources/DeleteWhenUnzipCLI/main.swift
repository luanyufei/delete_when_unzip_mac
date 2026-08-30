import CryptoKit
import Foundation
import DeleteWhenUnzipCore

@main
struct DeleteWhenUnzipCLI {

    static let version = "1.2.1"
    static let repoBase = "https://github.com/luanyufei/delete_when_unzip_mac"
    static let repoAPIBase = "https://api.github.com/repos/luanyufei/delete_when_unzip_mac"

    static let banner =
        """
        ========================================================
         dwum - DeleteWhenUnzipMac
         Streaming unzip with real-time APFS space reclamation
        ========================================================
        """

    static func printShortIntro() {
        print("""
        \(banner)

        Usage: dwum <archive-path> [chunk-size-MB] [password]
               dwum update            Check and upgrade to latest release

        For details run: dwum --help
        """)
    }

    static func printUsage() {
        print("""
        \(banner)

        Usage:
          dwum <archive-path> [chunk-size-MB] [password]
          dwum update               Check and automatically upgrade to latest release
          dwum --version | -v       Print version information
          dwum --help | -h          Print this help message

        Examples:
          dwum game.zip
          dwum game.part1.rar 10 mypassword
          dwum archive.z01 50
          dwum update

        Arguments:
          <archive-path>   Path to main archive or first volume (.zip, .rar, .part1.rar, .z01, etc.)
          [chunk-size-MB]  Buffer chunk size in MB (default: 10 MB)
          [password]       Archive extraction password (optional)
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
            print("Error: File does not exist -> \(fileURL.path)")
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

        print("Scanning and analyzing archive: \(fileURL.lastPathComponent)")

        let info: ArchiveInfo
        do {
            info = try ArchiveDetector.detect(mainFileURL: fileURL)
        } catch {
            print("Error: Archive detection failed: \(error.localizedDescription)")
            exit(1)
        }
        guard info.type.format != .other else {
            print("Error: Unsupported archive format. Supports ZIP, RAR, 7Z, TAR, GZIP, and split volumes.")
            exit(1)
        }

        // Encryption pre-probing
        var preferUnrar = false
        let probeResult = LibArchiveExtractor.probeEncryption(volumeURLs: info.volumeURLs, password: password)
        switch probeResult {
        case .passwordRequired where password == nil:
            print("Archive is encrypted.")
            guard let input = promptPassword("Enter extraction password:"), !input.isEmpty else {
                print("Error: No password provided. Cancelled.")
                exit(1)
            }
            password = input
        case .decoderUnsupported:
            if info.type.format == .rar {
                guard UnRARProcess.findUnRAR() != nil else {
                    print("Error: This archive uses RAR5 encryption which is not supported by libarchive.")
                    print("       Please install unrar: brew install --cask rar")
                    exit(1)
                }
                preferUnrar = true
                if password == nil {
                    print("Archive is encrypted (decrypting via unrar).")
                    guard let input = promptPassword("Enter extraction password:"), !input.isEmpty else {
                        print("Error: No password provided. Cancelled.")
                        exit(1)
                    }
                    password = input
                }
            } else {
                print("Error: \(ExtractionError.encryptedDecoderUnsupported(formatName: info.type.format.rawValue).localizedDescription)")
                exit(1)
            }
        case .unknown where info.type.format == .rar && UnRARProcess.findUnRAR() != nil:
            preferUnrar = true
        default:
            break
        }

        print("Format: \(info.type.displayName)")
        print("Output Directory: \(info.outputDirectoryURL.path)")
        print("Total Archive Size: \(info.formattedTotalSize)")
        if info.volumeURLs.count > 1 {
            print("Associated Volumes: \(info.volumeURLs.count) volumes")
            for (idx, vol) in info.volumeURLs.enumerated() {
                print("   [\(idx + 1)] \(vol.lastPathComponent)")
            }
        }

        let available = DiskSpaceMonitor.availableDiskSpace(at: fileURL)
        print("Available Disk Space: \(DiskSpaceMonitor.formatBytes(available))")
        print("Chunk Size: \(chunkSizeMB) MB")
        print("--------------------------------------------------------")
        print("Warning: Destructive operation! Source archive will be physically deleted during extraction.")
        print("Starting streaming extraction with real-time space reclamation...")
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
            print("\n\nExtraction completed! Total elapsed time: \(String(format: "%.1f", elapsed)) s")
            let endAvailable = DiskSpaceMonitor.availableDiskSpace(at: fileURL)
            print("Available Disk Space: \(DiskSpaceMonitor.formatBytes(endAvailable))")
            print("Extracted files saved to: \(info.outputDirectoryURL.path)")

        } catch {
            print("\n\nError: Extraction failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    // MARK: - Update

    private static func performUpdate() async {
        print("Checking for latest dwum release...")

        guard let latest = await fetchLatestRelease() else {
            print("Error: Failed to fetch version info. Please check network connection.")
            return
        }

        guard isNewerVersion(latest.version, than: version) else {
            print("You are already using the latest version (v\(version)).")
            return
        }

        print("New version available: v\(latest.version) (current: v\(version))")

        guard confirm("Upgrade to v\(latest.version) now? [y/n]") else {
            print("Update cancelled. You can download manually from https://github.com/luanyufei/delete_when_unzip_mac/releases")
            return
        }

        let resolvedPath = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        let isHomebrewInstalled = resolvedPath.contains("/Cellar/")

        if isHomebrewInstalled {
            await upgradeViaHomebrew()
        } else {
            await selfUpdate(assetURL: latest.assetURL, newVersion: latest.version)
        }
    }

    private static func fetchLatestRelease() async -> (version: String, assetURL: String?)? {
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
        print("Detected Homebrew installation, executing 'brew upgrade'...")
        let status = await runProcess("/usr/bin/env", ["brew", "upgrade", "dwum"],
                                      environment: ["HOMEBREW_NO_ASK": "1"],
                                      stdin: .nullDevice)
        guard status == 0 else {
            print("\nError: Homebrew upgrade failed (exit code \(status)). Try running 'brew update' first.")
            return
        }
        var installed = await captureProcess("/opt/homebrew/bin/brew", ["list", "--versions", "dwum"])
        if installed == nil {
            installed = await captureProcess("/usr/local/bin/brew", ["list", "--versions", "dwum"])
        }
        let upgradedVersion = (installed ?? "").split(separator: " ").last.map(String.init) ?? ""
        if !upgradedVersion.isEmpty && upgradedVersion != version {
            print("\nUpgrade complete! Currently installed: dwum \(upgradedVersion)")
            print("Run 'dwum' to use the new version.")
        } else {
            print("\nUpgrade command executed, but version unchanged (still v\(version)). Check Homebrew tap configuration.")
        }
    }

    private static func selfUpdate(assetURL: String?, newVersion: String) async {
        guard let assetURL, let downloadURL = URL(string: assetURL) else {
            print("Error: No macOS binary asset found for this release. Download manually from https://github.com/luanyufei/delete_when_unzip_mac/releases")
            return
        }

        print("Downloading dwum v\(newVersion)...")
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("dwum-update-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let (archiveURL, response) = try await URLSession.shared.download(from: downloadURL)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("Error: Download failed (HTTP \(httpResponse.statusCode)).")
                try? fm.removeItem(at: tmpDir)
                return
            }

            if let expected = await fetchSidecarChecksum(downloadURL) {
                let actual = try sha256Hex(of: archiveURL)
                guard actual == expected else {
                    print("Error: Checksum mismatch! Aborting update (expected \(expected.prefix(16))…, actual \(actual.prefix(16))…).")
                    try? fm.removeItem(at: tmpDir)
                    return
                }
                print("SHA-256 checksum verified.")
            } else {
                print("Warning: No checksum file provided for this release. Skipping integrity check.")
            }

            print("Extracting and verifying binary...")
            let extractStatus = await runProcess("/usr/bin/tar", ["-xzf", archiveURL.path, "-C", tmpDir.path])
            try? fm.removeItem(at: archiveURL)
            guard extractStatus == 0 else {
                print("Error: Failed to extract downloaded archive.")
                try? fm.removeItem(at: tmpDir)
                return
            }

            let newBinaryURL = tmpDir.appendingPathComponent("dwum")
            guard fm.fileExists(atPath: newBinaryURL.path) else {
                print("Error: dwum executable not found in archive.")
                try? fm.removeItem(at: tmpDir)
                return
            }

            guard let currentURL = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
                print("Error: Cannot determine current executable path.")
                try? fm.removeItem(at: tmpDir)
                return
            }

            let checkOutput = await captureProcess(newBinaryURL.path, ["--version"])
            guard checkOutput?.contains(newVersion) == true else {
                print("Error: New binary verification failed. Aborting update. Original file unchanged.")
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
                print("Error: Failed to replace binary, restored original: \(error.localizedDescription)")
                try? fm.removeItem(at: tmpDir)
                return
            }

            try? fm.removeItem(at: backupURL)
            try? fm.removeItem(at: tmpDir)
            print("\nUpdate complete! dwum upgraded to v\(newVersion).")
        } catch {
            print("Error: Automatic update failed: \(error.localizedDescription)")
            try? fm.removeItem(at: tmpDir)
        }
    }

    private enum ProcessStdin {
        case inherit
        case nullDevice
    }

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
        let padding = String(repeating: " ", count: max(0, lastProgressLineLength - line.count))
        lastProgressLineLength = max(line.count, lastProgressLineLength)
        FileHandle.standardOutput.write((line + padding).data(using: .utf8)!)
    }
}
