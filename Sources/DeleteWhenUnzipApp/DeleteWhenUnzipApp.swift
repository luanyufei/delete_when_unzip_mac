import SwiftUI
import AppKit
import DeleteWhenUnzipCore

// 文件打开事件 (Finder 双击 / open 命令) 统一由 AppDelegate 路由到主窗口，
// 避免 SwiftUI WindowGroup 为每个文件新建窗口
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: .openFileNotification, object: url)
        }
    }
}

@main
struct DeleteWhenUnzipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("DeleteWhenUnzipMac", id: "main") {
            ContentView()
                .frame(minWidth: 660, minHeight: 560)
        }
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
