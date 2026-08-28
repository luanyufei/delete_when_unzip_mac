import SwiftUI
import AppKit
import DeleteWhenUnzipCore

@main
struct DeleteWhenUnzipApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开压缩包...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        NotificationCenter.default.post(name: .openFileNotification, object: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .help) {
                Button("项目 GitHub 主页") {
                    if let url = URL(string: "https://github.com/auto-Dog/delete_when_unzip") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

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
