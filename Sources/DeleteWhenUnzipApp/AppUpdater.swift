import Foundation
import AppKit

public enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case upToDate(String)
    case updateAvailable(version: String, url: URL)
    case failed(String)
}

@MainActor
public final class AppUpdater: ObservableObject {
    public static let shared = AppUpdater()

    public static let currentVersion = "1.2.1"
    public static let repoOwner = "luanyufei"
    public static let repoName = "delete_when_unzip_mac"
    public static let repoURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)")!
    public static let authorGitHubURL = URL(string: "https://github.com/\(repoOwner)")!
    public static let authorEmail = "noonyufei@gmail.com"
    public static let upstreamRepoURL = URL(string: "https://github.com/auto-Dog/delete_when_unzip")!
    public static let upstreamAuthorURL = URL(string: "https://github.com/auto-Dog")!

    @Published public var status: UpdateCheckStatus = .idle
    @Published public var lastCheckTime: Date?

    private init() {}

    /// 检查更新
    /// - Parameter silent: 是否为静默后台检查（静默模式下若已是最新或失败不弹出显式错误提示）
    public func checkForUpdates(silent: Bool = false) {
        guard status != .checking else { return }
        status = .checking

        Task {
            do {
                guard let latestVersionTag = try await fetchLatestVersionTag() else {
                    throw NSError(domain: "AppUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析最新版本号"])
                }
                
                self.lastCheckTime = Date()

                if isVersion(latestVersionTag, newerThan: Self.currentVersion) {
                    let releaseURL = Self.repoURL.appendingPathComponent("releases/tag/v\(latestVersionTag)")
                    self.status = .updateAvailable(version: latestVersionTag, url: releaseURL)
                    
                    if !silent {
                        showUpdateAlert(version: latestVersionTag, releaseURL: releaseURL)
                    }
                } else {
                    self.status = .upToDate("v\(Self.currentVersion)")
                }
            } catch {
                if !silent {
                    self.status = .failed("检查更新失败: \(error.localizedDescription)")
                } else {
                    self.status = .idle
                }
            }
        }
    }

    /// 打开最新 Release 下载页面
    public func openReleasePage(url: URL? = nil) {
        let targetURL = url ?? Self.repoURL.appendingPathComponent("releases/latest")
        NSWorkspace.shared.open(targetURL)
    }

    // MARK: - 私有方法

    private func fetchLatestVersionTag() async throws -> String? {
        // 方案 1: GitHub Web 302 重定向拦截（完全不受 API 匿名 Rate Limit 限制，最稳定）
        let webURL = Self.repoURL.appendingPathComponent("releases/latest")
        var request = URLRequest(url: webURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8

        final class RedirectCatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
            var redirectedURL: URL?
            func urlSession(
                _ session: URLSession,
                task: URLSessionTask,
                willPerformHTTPRedirection response: HTTPURLResponse,
                newRequest request: URLRequest,
                completionHandler: @escaping (URLRequest?) -> Void
            ) {
                self.redirectedURL = request.url
                completionHandler(nil) // 终止重定向跟随
            }
        }

        let catcher = RedirectCatcher()
        let session = URLSession(configuration: .ephemeral, delegate: catcher, delegateQueue: nil)
        _ = try? await session.data(for: request)

        if let dest = catcher.redirectedURL {
            let tag = dest.lastPathComponent
            if tag != "latest" && tag != "releases" && !tag.isEmpty {
                return tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            }
        }

        // 方案 2: 降级走 GitHub REST API
        let apiURL = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest")!
        var apiReq = URLRequest(url: apiURL)
        apiReq.timeoutInterval = 8
        apiReq.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        apiReq.setValue("DeleteWhenUnzipMac/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: apiReq)
        if let http = response as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tag = json["tag_name"] as? String {
            return tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        }

        return nil
    }

    private func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let v1Components = v1.split(separator: ".").compactMap { Int($0) }
        let v2Components = v2.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(v1Components.count, v2Components.count)
        for i in 0..<maxCount {
            let part1 = i < v1Components.count ? v1Components[i] : 0
            let part2 = i < v2Components.count ? v2Components[i] : 0
            if part1 > part2 { return true }
            if part1 < part2 { return false }
        }
        return false
    }

    private func showUpdateAlert(version: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(version)"
        alert.informativeText = "DeleteWhenUnzipMac v\(version) 现已发布，建议更新以获得最新特性与性能优化。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后提醒")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openReleasePage(url: releaseURL)
        }
    }
}
