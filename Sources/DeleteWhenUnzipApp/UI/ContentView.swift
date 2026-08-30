import SwiftUI
import AppKit
import DeleteWhenUnzipCore

public final class ContentViewModel: ObservableObject {
    @Published public var showingSettings: Bool = false
    public init() {}
}

public struct ContentView: View {
    @StateObject private var engine = ExtractionEngine()
    @StateObject private var vm = ContentViewModel()
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
                        Text("正在分析压缩包结构与分卷信息...")
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
                        // 用户已在设置中关闭确认页: 直接开始
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
            .navigationTitle("DeleteWhenUnzipMac")
            .toolbar {
                ToolbarItem(placement: .status) {
                    if !engine.availableDiskSpaceFormatted.isEmpty {
                        Label("磁盘剩余 \(engine.availableDiskSpaceFormatted)", systemImage: "internaldrive")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.quinary, in: Capsule())
                            .help("当前磁盘可用空间")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("偏好设置")
                }
            }
        }
        .frame(minWidth: 660, minHeight: 560)
        .sheet(isPresented: $vm.showingSettings) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileNotification)) { notification in
            if let url = notification.object as? URL {
                engine.analyze(fileURL: url)
            }
        }
    }
}

// 完成页面
private struct CompletedView: View {
    let outputURL: URL
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("解压已顺利完成！")
                    .font(.title)
                    .fontWeight(.bold)

                Text("原始压缩文件已全部删除，目标文件已保存至：")
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
                    Label("在访达中显示", systemImage: "folder")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    onDone()
                } label: {
                    Text("完成")
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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 72))
                .foregroundStyle(.red)

            Text("解压遇到问题")
                .font(.title)
                .fontWeight(.bold)

            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            Button("返回重试") {
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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)

            Text("解压已被中止")
                .font(.title)
                .fontWeight(.bold)

            Text("注意：已解压的部分压缩数据可能已被销毁。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("返回主页") {
                onBack()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
