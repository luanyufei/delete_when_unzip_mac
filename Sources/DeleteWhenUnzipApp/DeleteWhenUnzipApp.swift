import SwiftUI
import AppKit
import DeleteWhenUnzipCore

// 文件打开事件 (Finder 双击 / open 命令) 统一由 AppDelegate 路由到主窗口，
// 避免 SwiftUI WindowGroup 为每个文件新建窗口
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LocalizationManager.shared.applyTheme()

        let autoCheck = UserDefaults.standard.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
        if autoCheck {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                AppUpdater.shared.checkForUpdates(silent: true)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: .openFileNotification, object: url)
        }
    }
}

@main
struct DeleteWhenUnzipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some Scene {
        Window("DeleteWhenUnzipMac", id: "main") {
            ContentView()
                .frame(minWidth: 480, minHeight: 540)
        }
        .defaultSize(width: 520, height: 600)
        .windowResizability(.contentMinSize)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

extension Notification.Name {
    static let openFileNotification = Notification.Name("openFileNotification")
}
