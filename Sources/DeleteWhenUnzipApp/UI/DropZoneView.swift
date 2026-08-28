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
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    vm.isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: vm.isTargeted ? 3 : 2, dash: vm.isTargeted ? [10] : [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(vm.isTargeted ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .animation(.easeInOut(duration: 0.2), value: vm.isTargeted)

            VStack(spacing: 16) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(vm.isTargeted ? Color.accentColor : Color.secondary)
                    .scaleEffect(vm.isTargeted ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.isTargeted)

                VStack(spacing: 6) {
                    Text("拖拽压缩文件到此处")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("支持单文件及多分卷 (.zip, .rar, .z01, .part1.rar, .7z.001)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    chooseFile()
                } label: {
                    Label("浏览文件 (Choose File)", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(24)
        }
        .frame(minHeight: 220)
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
