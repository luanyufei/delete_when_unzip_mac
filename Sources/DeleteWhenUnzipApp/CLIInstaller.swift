import Foundation
import AppKit

@MainActor
public final class CLIInstaller: ObservableObject {
    public static let shared = CLIInstaller()

    @Published public var isInstalled: Bool = false
    @Published public var installedLocation: String? = nil
    @Published public var installedVersion: String? = nil
    @Published public var statusMessage: String = ""

    private let targetPaths = [
        "/usr/local/bin/dwum",
        "/opt/homebrew/bin/dwum"
    ]

    private init() {
        checkStatus()
    }

    /// 检查 CLI 安装状态与版本
    public func checkStatus() {
        for path in targetPaths {
            if FileManager.default.fileExists(atPath: path) {
                self.isInstalled = true
                self.installedLocation = path
                self.installedVersion = fetchInstalledVersion(at: path) ?? "v\(AppUpdater.currentVersion)"
                return
            }
        }
        self.isInstalled = false
        self.installedLocation = nil
        self.installedVersion = nil
    }

    /// 执行一键安装或更新到 /usr/local/bin/dwum
    public func installOrUpdate() {
        guard let sourceURL = Bundle.main.url(forResource: "dwum", withExtension: nil) ??
                Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/dwum") as URL? else {
            self.statusMessage = "未在 App Bundle 中找到 dwum 二进制"
            return
        }

        let sourcePath = sourceURL.path
        let targetPath = "/usr/local/bin/dwum"

        do {
            let targetDir = URL(fileURLWithPath: "/usr/local/bin")
            if !FileManager.default.fileExists(atPath: targetDir.path) {
                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: targetPath) {
                try FileManager.default.removeItem(atPath: targetPath)
            }
            try FileManager.default.createSymbolicLink(atPath: targetPath, withDestinationPath: sourcePath)
            self.statusMessage = isInstalled ? "已更新至最新版 (v\(AppUpdater.currentVersion))" : "安装成功！"
            checkStatus()
            return
        } catch {
            let appleScript = """
            do shell script "mkdir -p /usr/local/bin && ln -sf '\(sourcePath)' /usr/local/bin/dwum" with administrator privileges
            """
            var errorDict: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScript) {
                scriptObject.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let errMsg = error[NSAppleScript.errorMessage] as? String ?? "操作被取消"
                    self.statusMessage = errMsg
                } else {
                    self.statusMessage = isInstalled ? "已更新至最新版 (v\(AppUpdater.currentVersion))" : "安装成功！"
                    checkStatus()
                }
            }
        }
    }

    /// 检查更新 CLI
    public func checkForUpdate() {
        checkStatus()
        guard isInstalled else {
            installOrUpdate()
            return
        }
        
        let currentAppVer = "v\(AppUpdater.currentVersion)"
        if let currentCLI = installedVersion, currentCLI == currentAppVer {
            self.statusMessage = "当前 CLI 已是最新版本 (\(currentAppVer))"
        } else {
            installOrUpdate()
        }
    }

    private func fetchInstalledVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-v"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if let match = output.range(of: "v[0-9.]+", options: .regularExpression) {
                    return String(output[match])
                }
                return output
            }
        } catch {}
        return nil
    }
}
