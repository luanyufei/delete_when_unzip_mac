import AppKit
import SwiftUI

/// 规避 CommandLineTools 工具链缺失 SwiftUI 宏插件的问题:
/// 该目标内禁用 @State/@Binding 宏，状态一律走 ObservableObject。
final class SettingsViewModel: ObservableObject {
    @Published var selection: SettingsTab = .general
    @Published var emailCopied = false
    init() {}
}

enum SettingsTab: Hashable {
    case general, about

    var title: String {
        switch self {
        case .general: return "通用"
        case .about: return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .about: return "person.crop.circle"
        }
    }
}

public struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @AppStorage("defaultChunkSizeMB") private var defaultChunkSizeMB: Int = 10
    @AppStorage("autoRevealInFinder") private var autoRevealInFinder: Bool = true
    @AppStorage("showDestructiveWarning") private var showDestructiveWarning: Bool = true

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: Binding(get: { vm.selection }, set: { vm.selection = $0 })) {
                ForEach([SettingsTab.general, .about], id: \.self) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("设置")
        } detail: {
            switch vm.selection {
            case .general: GeneralSettingsPane()
            case .about: AboutSettingsPane()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 620, minHeight: 430)
    }
}

// MARK: - 通用设置

private struct GeneralSettingsPane: View {
    @AppStorage("defaultChunkSizeMB") private var defaultChunkSizeMB: Int = 10
    @AppStorage("autoRevealInFinder") private var autoRevealInFinder: Bool = true
    @AppStorage("showDestructiveWarning") private var showDestructiveWarning: Bool = true

    var body: some View {
        Form {
            Section("解压与性能") {
                Stepper(value: $defaultChunkSizeMB, in: 1...2048, step: 5) {
                    HStack {
                        Text("默认分块大小")
                        Spacer()
                        Text("\(defaultChunkSizeMB) MB")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .noFocusEffect()
                Text("分块大小影响空间回收频率与内存占用。推荐 10 ~ 50 MB。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自动化行为") {
                Toggle("解压完成后在访达中显示目标文件夹", isOn: $autoRevealInFinder)
                Toggle("每次解压前显示不可逆删除确认", isOn: $showDestructiveWarning)
            }

            Section("关于核心机制") {
                LabeledContent("空间回收策略") {
                    Text("APFS 零拷贝物理打洞 (F_PUNCHHOLE)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("非 APFS 文件系统") {
                    Text("自动回退为平移截断")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("解压引擎") {
                    Text("libarchive + unrar (原生)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("版本") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

// MARK: - 关于

private struct AboutSettingsPane: View {
    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    AsyncImage(url: URL(string: "https://github.com/luanyufei.png")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                    VStack(spacing: 4) {
                        Text("luanyufei")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("DeleteWhenUnzipMac 作者")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("联系方式") {
                LabeledContent {
                    HStack(spacing: 8) {
                        Link("noonyufei@gmail.com", destination: URL(string: "mailto:noonyufei@gmail.com")!)
                            .font(.callout)
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString("noonyufei@gmail.com", forType: .string)
                            vm.emailCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                vm.emailCopied = false
                            }
                        } label: {
                            Image(systemName: vm.emailCopied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("复制邮箱地址")
                    }
                } label: {
                    Label("邮箱", systemImage: "envelope")
                }

                LabeledContent {
                    Link("@luanyufei", destination: URL(string: "https://github.com/luanyufei")!)
                        .font(.callout)
                } label: {
                    Label("GitHub", systemImage: "link")
                }
            }

            Section("项目") {
                LabeledContent {
                    Link("github.com/luanyufei/delete_when_unzip_mac",
                         destination: URL(string: "https://github.com/luanyufei/delete_when_unzip_mac")!)
                        .font(.callout)
                } label: {
                    Label("项目地址", systemImage: "square.and.arrow.up.on.square")
                }
                Text("灵感与致敬: auto-Dog/delete_when_unzip · macOS 原生重写: luanyufei")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

// MARK: - 焦点环抑制

extension View {
    /// 去除控件获得键盘焦点时的蓝色光环 (macOS 14+；低版本系统无此效果可忽略)
    @ViewBuilder
    func noFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled(true)
        } else {
            self
        }
    }
}
