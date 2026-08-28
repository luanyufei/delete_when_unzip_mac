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

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HeaderView(engine: engine, onOpenSettings: { vm.showingSettings = true })
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // 主视图状态路由
            ZStack {
                switch engine.state {
                case .idle:
                    DropZoneView { fileURL in
                        engine.analyze(fileURL: fileURL)
                    }
                    .padding(20)

                case .analyzing:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("正在分析压缩包结构与分卷信息...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let info):
                    WarningSheet(
                        info: info,
                        onConfirm: { password, chunkSizeMB in
                            engine.startExtraction(info: info, password: password, chunkSizeMB: chunkSizeMB)
                        },
                        onCancel: {
                            engine.reset()
                        }
                    )

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
                    .padding(20)

                case .completed(let outputURL):
                    CompletedView(outputURL: outputURL) {
                        engine.reset()
                    }
                    .padding(20)
                    .onAppear {
                        if autoRevealInFinder {
                            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                        }
                    }

                case .failed(let error):
                    ErrorView(error: error) {
                        engine.reset()
                    }
                    .padding(20)

                case .cancelled:
                    CancelledView {
                        engine.reset()
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 460)
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

// 头部状态栏
private struct HeaderView: View {
    @ObservedObject var engine: ExtractionEngine
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.tint)
                    Text("DeleteWhenUnzipMac")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text("边解压边删除 · APFS 物理打洞零写入损耗")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !engine.availableDiskSpaceFormatted.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                    Text("磁盘剩余: \(engine.availableDiskSpaceFormatted)")
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
            }

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("偏好设置")
        }
    }
}

// 完成页面
private struct CompletedView: View {
    let outputURL: URL
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("解压已顺利完成！")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("原始压缩文件已全部删除，目标文件已保存至：")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(outputURL.path)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    onDone()
                } label: {
                    Text("完成")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// 错误页面
private struct ErrorView: View {
    let error: ExtractionError
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)

            Text("解压遇到问题")
                .font(.title3)
                .fontWeight(.bold)

            Text(error.localizedDescription)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Button("返回重试 (Back)") {
                onBack()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// 中止页面
private struct CancelledView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)

            Text("解压已被中止")
                .font(.title3)
                .fontWeight(.bold)

            Text("注意：已解压的部分压缩数据可能已被销毁。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("返回主页") {
                onBack()
            }
            .buttonStyle(.bordered)
        }
    }
}
