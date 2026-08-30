import SwiftUI
import AppKit

public final class DropZoneViewModel: ObservableObject {
    @Published public var isTargeted: Bool = false
    public init() {}
}

public struct DropZoneView: View {
    let onFileSelected: (URL) -> Void
    @StateObject private var vm = DropZoneViewModel()

    public init(onFileSelected: @escaping (URL) -> Void) {
        self.onFileSelected = onFileSelected
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    .scaleEffect(vm.isTargeted ? 1.06 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.isTargeted)

                VStack(spacing: 8) {
                    Text(vm.isTargeted ? "松开即可开始分析" : "拖入压缩包，边解压边释放空间")
                        .font(.title2)
                        .fontWeight(.bold)
                        .animation(.easeInOut(duration: 0.15), value: vm.isTargeted)

                    Text("单文件与多分卷: ZIP · RAR · 7Z · TAR · GZIP · .part1.rar · .z01 · .7z.001")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    chooseFile()
                } label: {
                    Label("选取文件…", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .noFocusEffect()
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: 340)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(vm.isTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        vm.isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: vm.isTargeted ? 3 : 2, dash: vm.isTargeted ? [] : [8])
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: vm.isTargeted)

            Spacer()

            Label("解压过程中原压缩包将被逐步删除，磁盘空间实时回收", systemImage: "shield.checkerboard")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            onFileSelected(first)
            return true
        } isTargeted: { targeted in
            self.vm.isTargeted = targeted
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择压缩包"
        panel.message = "请选择主压缩文件或首个分卷文件"

        if panel.runModal() == .OK, let url = panel.url {
            onFileSelected(url)
        }
    }
}
