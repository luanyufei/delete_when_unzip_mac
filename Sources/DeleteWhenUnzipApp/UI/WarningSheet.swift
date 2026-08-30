import SwiftUI
import DeleteWhenUnzipCore

public final class WarningSheetViewModel: ObservableObject {
    @Published public var password: String = ""
    @Published public var hasPassword: Bool = false
    public init() {}
}

public struct WarningSheet: View {
    let info: ArchiveInfo
    let requiresPassword: Bool
    let onConfirm: (String?, Int) -> Void
    let onCancel: () -> Void

    @StateObject private var vm = WarningSheetViewModel()
    @AppStorage("defaultChunkSizeMB") private var chunkSizeMB: Int = 10

    public init(
        info: ArchiveInfo,
        requiresPassword: Bool = false,
        onConfirm: @escaping (String?, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.info = info
        self.requiresPassword = requiresPassword
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 5) {
                    Text("确认边解压边删除")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("解压过程中原始压缩包将被逐步物理销毁，不可撤销。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // 文件分析信息卡片
            VStack(spacing: 12) {
                InfoRow(label: "主文件", value: info.mainVolumeURL.lastPathComponent, icon: "doc.zipper")
                InfoRow(label: "识别格式", value: info.type.displayName, icon: "cube.box")
                InfoRow(label: "总压缩大小", value: info.formattedTotalSize, icon: "internaldrive")
                if info.volumeURLs.count > 1 {
                    InfoRow(label: "分卷数量", value: "\(info.volumeURLs.count) 卷", icon: "square.stack.3d.down.right")
                }
                InfoRow(label: "解压目标", value: info.outputDirectoryURL.path, icon: "folder")
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // 密码与高级设置
            VStack(alignment: .leading, spacing: 12) {
                if requiresPassword {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Text("检测到该压缩包已加密，必须提供密码后才能解压")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    SecureField("解压密码", text: $vm.password)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onAppear { vm.hasPassword = true }
                } else {
                    Toggle("压缩包包含密码 (Encrypted)", isOn: $vm.hasPassword.animation())
                        .font(.body)

                    if vm.hasPassword {
                        SecureField("输入解压密码", text: $vm.password)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                    }
                }

                HStack {
                    Text("处理块大小 (Chunk Size):")
                        .font(.body)
                    Spacer()
                    Stepper("\(chunkSizeMB) MB", value: $chunkSizeMB, in: 1...2048, step: 5)
                        .font(.body)
                }
            }

            Spacer()

            HStack {
                Button("取消 (Cancel)", role: .cancel) {
                    onCancel()
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    let pwd = vm.hasPassword && !vm.password.isEmpty ? vm.password : nil
                    onConfirm(pwd, chunkSizeMB)
                } label: {
                    Label("我已知晓风险，开始解压", systemImage: "bolt.fill")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(requiresPassword && vm.password.isEmpty)
            }
        }
        .padding(28)
        .frame(maxWidth: 640, minHeight: 480)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
