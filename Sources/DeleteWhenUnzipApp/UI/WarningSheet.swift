import SwiftUI
import DeleteWhenUnzipCore

public final class WarningSheetViewModel: ObservableObject {
    @Published public var password: String = ""
    @Published public var hasPassword: Bool = false
    public init() {}
}

public struct WarningSheet: View {
    let info: ArchiveInfo
    let onConfirm: (String?, Int) -> Void
    let onCancel: () -> Void

    @StateObject private var vm = WarningSheetViewModel()
    @AppStorage("defaultChunkSizeMB") private var chunkSizeMB: Int = 10

    public init(
        info: ArchiveInfo,
        onConfirm: @escaping (String?, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.info = info
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("确认边解压边删除")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("解压过程中原始压缩包将被逐步物理销毁，不可撤销。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // 文件分析信息卡片
            VStack(spacing: 10) {
                InfoRow(label: "主文件", value: info.mainVolumeURL.lastPathComponent, icon: "doc.zipper")
                InfoRow(label: "识别格式", value: info.type.displayName, icon: "cube.box")
                InfoRow(label: "总压缩大小", value: info.formattedTotalSize, icon: "internaldrive")
                if info.volumeURLs.count > 1 {
                    InfoRow(label: "分卷数量", value: "\(info.volumeURLs.count) 卷", icon: "square.stack.3d.down.right")
                }
                InfoRow(label: "解压目标", value: info.outputDirectoryURL.path, icon: "folder")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 密码与高级设置
            VStack(alignment: .leading, spacing: 10) {
                Toggle("压缩包包含密码 (Encrypted)", isOn: $vm.hasPassword.animation())
                    .font(.subheadline)

                if vm.hasPassword {
                    SecureField("输入解压密码", text: $vm.password)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("处理块大小 (Chunk Size):")
                        .font(.subheadline)
                    Spacer()
                    Stepper("\(chunkSizeMB) MB", value: $chunkSizeMB, in: 1...2048, step: 5)
                        .font(.subheadline)
                }
            }

            Spacer()

            HStack {
                Button("取消 (Cancel)", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    let pwd = vm.hasPassword && !vm.password.isEmpty ? vm.password : nil
                    onConfirm(pwd, chunkSizeMB)
                } label: {
                    Label("我已知晓风险，开始解压", systemImage: "bolt.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 440)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
