import AppKit
import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "general"
    case appearance = "appearance"
    case about = "about"

    public var id: String { rawValue }

    @MainActor
    public func title(using l10n: LocalizationManager) -> String {
        switch self {
        case .general: return l10n.t("tab_general")
        case .appearance: return l10n.t("tab_appearance")
        case .about: return l10n.t("tab_about")
        }
    }

    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .about: return "info.circle.fill"
        }
    }
}

final class SettingsState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
    init() {}
}

public struct SettingsView: View {
    @StateObject private var state = SettingsState()
    @ObservedObject private var l10n = LocalizationManager.shared
    @StateObject private var updater = AppUpdater.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部优雅分段切换器 (参考 WO MIC 布局，消除侧边栏界限，去除蓝色焦点环)
            Picker("", selection: $state.selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title(using: l10n), systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .focusable(false)
            .noFocusEffect()
            .frame(width: 300)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .opacity(0.6)

            // 内容区域
            Group {
                switch state.selectedTab {
                case .general:
                    GeneralSettingsPane()
                case .appearance:
                    AppearanceSettingsPane()
                case .about:
                    AboutSettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 640)
    }
}

// MARK: - 通用设置

private struct GeneralSettingsPane: View {
    @StateObject private var cli = CLIInstaller.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("defaultChunkSizeMB") private var defaultChunkSizeMB: Int = 10
    @AppStorage("autoRevealInFinder") private var autoRevealInFinder: Bool = true
    @AppStorage("showDestructiveWarning") private var showDestructiveWarning: Bool = true

    var body: some View {
        Form {
            Section(l10n.t("section_perf")) {
                Stepper(value: $defaultChunkSizeMB, in: 1...2048, step: 5) {
                    HStack {
                        Text(l10n.t("default_chunk_size"))
                        Spacer()
                        Text("\(defaultChunkSizeMB) MB")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .noFocusEffect()
                Text(l10n.t("chunk_size_tip"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.t("section_cli")) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("cli_name"))
                            .font(.body)
                        if cli.isInstalled {
                            Text("\(l10n.t("cli_installed_prefix")) \(cli.installedLocation ?? "/usr/local/bin/dwum") · \(cli.installedVersion ?? "v\(AppUpdater.currentVersion)")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(l10n.t("cli_not_installed"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if cli.isInstalled {
                        Button(l10n.t("cli_check_update")) {
                            cli.checkForUpdate()
                        }
                        .controlSize(.small)
                        .noFocusEffect()
                    } else {
                        Button(l10n.t("cli_get_latest")) {
                            cli.installOrUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .noFocusEffect()
                    }
                }
                if !cli.statusMessage.isEmpty {
                    Text(cli.statusMessage)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Section(l10n.t("section_automation")) {
                Toggle(l10n.t("auto_reveal_finder"), isOn: $autoRevealInFinder)
                    .toggleStyle(.switch)
                    .noFocusEffect()
                Toggle(l10n.t("show_destructive_warning"), isOn: $showDestructiveWarning)
                    .toggleStyle(.switch)
                    .noFocusEffect()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

// MARK: - 外观设置 (语言与深浅色模式)

private struct AppearanceSettingsPane: View {
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        Form {
            Section(l10n.t("section_language")) {
                HStack {
                    Label(l10n.t("language_label"), systemImage: "globe")
                        .font(.body)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { l10n.currentLanguage },
                        set: { l10n.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .noFocusEffect()
                }
            }

            Section(l10n.t("section_theme")) {
                HStack {
                    Label(l10n.t("theme_label"), systemImage: "circle.lefthalf.filled")
                        .font(.body)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { l10n.currentTheme },
                        set: { l10n.setTheme($0) }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName(using: l10n)).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .noFocusEffect()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

// MARK: - 关于 (完全按图 2 样式与致敬卡片设计)

private struct AboutSettingsPane: View {
    @ObservedObject private var l10n = LocalizationManager.shared
    @StateObject private var updater = AppUpdater.shared
    @AppStorage("automaticallyChecksForUpdates") private var autoCheckUpdates: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. 软件信息卡片
                SettingsCardView {
                    HStack(alignment: .center, spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("DeleteWhenUnzipMac")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Text("\(l10n.t("version_prefix")) \(AppUpdater.currentVersion)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }

                            Text(l10n.t("about_desc"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Button {
                            NSWorkspace.shared.open(AppUpdater.repoURL)
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("GitHub Repository")
                    }
                    .padding(16)
                }

                // 2. 关于作者卡片 (使用本地内置头像，秒级即时加载)
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("section_author"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    SettingsCardView {
                        HStack(alignment: .center, spacing: 14) {
                            authorAvatarView

                            VStack(alignment: .leading, spacing: 3) {
                                Text("FEEFEENOON")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Link(AppUpdater.authorEmail, destination: URL(string: "mailto:\(AppUpdater.authorEmail)")!)
                                    .font(.callout)
                            }

                            Spacer()

                            Button {
                                NSWorkspace.shared.open(AppUpdater.authorGitHubURL)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("GitHub Profile")
                        }
                        .padding(16)
                    }
                }

                // 3. 灵感与致敬 (原项目与原作者)
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("section_tribute"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    SettingsCardView {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(Color.red.opacity(0.85))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("auto-Dog / delete_when_unzip")
                                    .font(.headline)
                                    .fontWeight(.bold)

                                Text(l10n.t("tribute_desc"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                NSWorkspace.shared.open(AppUpdater.upstreamRepoURL)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Upstream Repository")
                        }
                        .padding(16)
                    }
                }

                // 4. 软件更新卡片 (字靠左、Switch 靠右、按钮与状态完美对齐)
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("section_update"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    SettingsCardView {
                        VStack(spacing: 0) {
                            // 第一行: 文字居左，Switch 居右
                            HStack {
                                Text(l10n.t("auto_update_toggle"))
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: $autoCheckUpdates)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .noFocusEffect()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider()
                                .opacity(0.6)

                            // 第二行: 按钮居左，状态提示居右
                            HStack {
                                Button {
                                    updater.checkForUpdates(silent: false)
                                } label: {
                                    Text(l10n.t("check_update_btn"))
                                }
                                .controlSize(.small)
                                .noFocusEffect()
                                .disabled(updater.status == .checking)

                                Spacer()

                                switch updater.status {
                                case .idle:
                                    EmptyView()
                                case .checking:
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text(l10n.t("checking_update"))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                case .upToDate(let ver):
                                    Text("\(l10n.t("up_to_date")) (\(ver))")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                case .updateAvailable(let newVer, let url):
                                    Button {
                                        updater.openReleasePage(url: url)
                                    } label: {
                                        Label("\(l10n.t("new_version")) v\(newVer)", systemImage: "arrow.down.circle.fill")
                                            .font(.callout)
                                            .fontWeight(.medium)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(Color.accentColor)
                                case .failed(let msg):
                                    Text(msg)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    // 本地内置作者头像视图
    @ViewBuilder
    private var authorAvatarView: some View {
        if let avatarURL = Bundle.main.url(forResource: "AuthorAvatar", withExtension: "png"),
           let nsImage = NSImage(contentsOf: avatarURL) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        } else if let localFallback = NSImage(contentsOfFile: "Sources/DeleteWhenUnzipApp/AuthorAvatar.png") {
            Image(nsImage: localFallback)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 原生卡片容器

private struct SettingsCardView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - 辅助扩展

extension View {
    @ViewBuilder
    func noFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled(true)
        } else {
            self
        }
    }
}
