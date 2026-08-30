import SwiftUI
import AppKit

public final class DropZoneViewModel: ObservableObject {
    @Published public var isTargeted: Bool = false
    public init() {}
}

public struct DropZoneView: View {
    let onFileSelected: (URL) -> Void
    @StateObject private var vm = DropZoneViewModel()
    @ObservedObject private var l10n = LocalizationManager.shared
    @Environment(\.colorScheme) private var colorScheme

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
                    Text(vm.isTargeted ? l10n.t("drop_title_targeted") : l10n.t("drop_title"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .animation(.easeInOut(duration: 0.15), value: vm.isTargeted)

                    Text(l10n.t("drop_formats"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    chooseFile()
                } label: {
                    Label(l10n.t("choose_file"), systemImage: "folder.badge.plus")
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
                    .fill(
                        vm.isTargeted ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.6)
                    )
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
        panel.prompt = l10n.t("choose_file")

        if panel.runModal() == .OK, let url = panel.url {
            onFileSelected(url)
        }
    }
}
