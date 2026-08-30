import SwiftUI
import AppKit
import DeleteWhenUnzipCore

public struct ContentView: View {
    @StateObject private var engine = ExtractionEngine()
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("autoRevealInFinder") private var autoRevealInFinder: Bool = true
    @AppStorage("showDestructiveWarning") private var showDestructiveWarning: Bool = true
    @AppStorage("defaultChunkSizeMB") private var defaultChunkSizeMB: Int = 10

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                switch engine.state {
                case .idle:
                    DropZoneView { fileURL in
                        engine.analyze(fileURL: fileURL)
                    }
                    .padding(28)

                case .analyzing:
                    VStack(spacing: 20) {
                        ProgressView()
                            .controlSize(.large)
                        Text(l10n.t("analyzing"))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let info):
                    if showDestructiveWarning {
                        WarningSheet(
                            info: info,
                            requiresPassword: engine.requiresPassword,
                            onConfirm: { password, chunkSizeMB in
                                engine.startExtraction(info: info, password: password, chunkSizeMB: chunkSizeMB)
                            },
                            onCancel: {
                                engine.reset()
                            }
                        )
                    } else {
                        Color.clear
                            .onAppear {
                                engine.startExtraction(info: info, password: nil, chunkSizeMB: defaultChunkSizeMB)
                            }
                    }

                case .extracting(let progress, let fileName, let processed, let total, let speed):
                    ExtractionProgressView(
                        progress: progress,
                        currentFileName: fileName,
                        processedSize: processed,
                        totalSize: total,
                        speed: speed,
                        availableDiskSpace: engine.availableDiskSpaceFormatted,
                        onCancel: {
                            engine.cancel()
                        }
                    )
                    .padding(28)

                case .completed(let outputURL):
                    CompletedView(outputURL: outputURL) {
                        engine.reset()
                    }
                    .padding(28)
                    .onAppear {
                        if autoRevealInFinder {
                            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                        }
                    }

                case .failed(let error):
                    ErrorView(error: error) {
                        engine.reset()
                    }
                    .padding(28)

                case .cancelled:
                    CancelledView {
                        engine.reset()
                    }
                    .padding(28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(l10n.t("app_name"))
            .toolbar {
                ToolbarItem(placement: .status) {
                    if !engine.availableDiskSpaceFormatted.isEmpty {
                        Label("\(l10n.t("disk_free")) \(engine.availableDiskSpaceFormatted)", systemImage: "internaldrive")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                            .help(l10n.t("disk_free"))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    openSettingsButton
                }
            }
        }
        .frame(minWidth: 480, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(for: .openFileNotification)) { notification in
            if let url = notification.object as? URL {
                engine.analyze(fileURL: url)
            }
        }
    }

    @ViewBuilder
    private var openSettingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help(l10n.t("tab_general"))
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .help(l10n.t("tab_general"))
        }
    }
}

// 完成页面
private struct CompletedView: View {
    let outputURL: URL
    let onDone: () -> Void
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text(l10n.t("completed_title"))
                    .font(.title)
                    .fontWeight(.bold)

                Text(l10n.t("completed_desc"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(outputURL.path)
                .font(.callout)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 14) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } label: {
                    Label(l10n.t("reveal_in_finder"), systemImage: "folder")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    onDone()
                } label: {
                    Text(l10n.t("done"))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 错误页面
private struct ErrorView: View {
    let error: ExtractionError
    let onBack: () -> Void
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)

            Text(l10n.t("failed_title"))
                .font(.title)
                .fontWeight(.bold)

            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            Button(l10n.t("back")) {
                onBack()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 中止页面
private struct CancelledView: View {
    let onBack: () -> Void
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)

            Text(l10n.t("cancelled_title"))
                .font(.title)
                .fontWeight(.bold)

            Button(l10n.t("back")) {
                onBack()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
