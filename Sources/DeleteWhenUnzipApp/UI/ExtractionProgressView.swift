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
    @ObservedObject private var l10n = LocalizationManager.shared

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
                Text(l10n.t("extracting_title"))
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
                StatItem(title: "\(l10n.t("processed")) / \(l10n.t("total_size"))", value: "\(processedSize) / \(totalSize)", icon: "internaldrive")
                StatItem(title: l10n.t("speed"), value: speed, icon: "speedometer")
                if !availableDiskSpace.isEmpty {
                    StatItem(title: l10n.t("disk_free"), value: availableDiskSpace, icon: "opticaldiscdrive")
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer()

            HStack {
                Spacer()

                Button(l10n.t("cancel_extraction"), role: .destructive) {
                    vm.showingCancelConfirm = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .confirmationDialog(l10n.t("cancel_extraction"), isPresented: $vm.showingCancelConfirm) {
                    Button(l10n.t("cancel_extraction"), role: .destructive) {
                        onCancel()
                    }
                    Button(l10n.t("cancel"), role: .cancel) {}
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
