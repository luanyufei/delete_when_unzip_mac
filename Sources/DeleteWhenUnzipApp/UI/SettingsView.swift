import SwiftUI

public struct SettingsView: View {
    @AppStorage("defaultChunkSizeMB") private var defaultChunkSizeMB: Int = 10
    @AppStorage("autoRevealInFinder") private var autoRevealInFinder: Bool = true
    @AppStorage("showDestructiveWarning") private var showDestructiveWarning: Bool = true

    public init() {}

    public var body: some View {
        Form {
            Section("解压与性能 (Extraction & Performance)") {
                Stepper(value: $defaultChunkSizeMB, in: 1...2048, step: 5) {
                    HStack {
                        Text("默认分块大小 (Chunk Size):")
                        Spacer()
                        Text("\(defaultChunkSizeMB) MB")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text("在 APFS 文件系统上，分块大小影响物理打洞频率；在其他文件系统上影响内存与平移缓存。推荐 10 ~ 50 MB。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自动化行为 (Automation)") {
                Toggle("解压完成后在访达 (Finder) 中显示目标文件夹", isOn: $autoRevealInFinder)
                Toggle("每次解压前弹出不可逆删除确认警告", isOn: $showDestructiveWarning)
            }

            Section("关于核心机制 (Architecture)") {
                LabeledContent("空间回收策略") {
                    Text("APFS 零拷贝物理打洞 (F_PUNCHHOLE)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("解压引擎") {
                    Text("Native libarchive (C / Swift 6)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        .padding(12)
    }
}
