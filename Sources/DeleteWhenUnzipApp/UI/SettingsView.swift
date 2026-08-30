import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultChunkSizeMB") private var defaultChunkSizeMB: Int = 10
    @AppStorage("autoRevealInFinder") private var autoRevealInFinder: Bool = true
    @AppStorage("showDestructiveWarning") private var showDestructiveWarning: Bool = true

    public init() {}

    public var body: some View {
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
        .frame(width: 520, height: 420)
    }
}
