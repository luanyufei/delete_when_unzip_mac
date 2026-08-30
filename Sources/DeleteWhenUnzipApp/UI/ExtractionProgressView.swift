import SwiftUI

public final class ProgressViewModel: ObservableObject {
    @Published public var showingCancelConfirm: Bool = false
    public init() {}
}

public struct ExtractionProgressView: View {
    let progress: Double
    let currentFileName: String
    let processedSize: String
    let totalSize: String
    let speed: String
    let availableDiskSpace: String
    let onCancel: () -> Void

    @StateObject private var vm = ProgressViewModel()

    public init(
        progress: Double,
        currentFileName: String,
        processedSize: String,
        totalSize: String,
        speed: String,
        availableDiskSpace: String,
        onCancel: @escaping () -> Void
    ) {
        self.progress = progress
        self.currentFileName = currentFileName
        self.processedSize = processedSize
        self.totalSize = totalSize
        self.speed = speed
        self.availableDiskSpace = availableDiskSpace
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("正在流式解压并释放空间")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(currentFileName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("\(Int(progress * 100))%")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .monospacedDigit()
                .contentTransition(.numericText())

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack(spacing: 28) {
                StatItem(title: "已处理 / 总大小", value: "\(processedSize) / \(totalSize)", icon: "internaldrive")
                StatItem(title: "实时解压速度", value: speed, icon: "speedometer")
                if !availableDiskSpace.isEmpty {
                    StatItem(title: "磁盘剩余", value: availableDiskSpace, icon: "opticaldiscdrive")
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer()

            HStack {
                Text("中途强行终止可能导致压缩文件损坏且解压不完整")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("中止解压", role: .destructive) {
                    vm.showingCancelConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .confirmationDialog("确定要中止解压吗？", isPresented: $vm.showingCancelConfirm) {
                    Button("确认中止（源文件已部分损坏）", role: .destructive) {
                        onCancel()
                    }
                    Button("继续解压", role: .cancel) {}
                } message: {
                    Text("当前已解压部分已被删除，中止将导致压缩文件不完整且无法继续解压。")
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 640, minHeight: 320)
    }
}

private struct StatItem: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
