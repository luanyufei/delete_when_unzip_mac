import Foundation
import Combine

public enum EngineState: Sendable, Equatable {
    case idle
    case analyzing
    case ready(ArchiveInfo)
    case extracting(progress: Double, fileName: String, processedSize: String, totalSize: String, speed: String)
    case completed(outputURL: URL)
    case failed(ExtractionError)
    case cancelled

    public static func == (lhs: EngineState, rhs: EngineState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.analyzing, .analyzing), (.cancelled, .cancelled):
            return true
        case (.ready(let a), .ready(let b)):
            return a.id == b.id
        case (.extracting(let p1, let f1, _, _, _), .extracting(let p2, let f2, _, _, _)):
            return p1 == p2 && f1 == f2
        case (.completed(let u1), .completed(let u2)):
            return u1 == u2
        case (.failed(let e1), .failed(let e2)):
            return e1.localizedDescription == e2.localizedDescription
        default:
            return false
        }
    }
}

@MainActor
public final class ExtractionEngine: ObservableObject {

    @Published public var state: EngineState = .idle
    @Published public var currentInfo: ArchiveInfo?
    @Published public var availableDiskSpaceFormatted: String = ""
    /// 加密预探测结论: 为 .passwordRequired 时 UI 必须先收集密码
    @Published public var requiresPassword: Bool = false

    private var extractionTask: Task<Void, Never>?
    private var startTime: Date?
    private var lastBytes: UInt64 = 0
    private var lastTime: Date?
    private var encryptionProbe: ArchiveEncryption = .unknown

    public init() {}

    public func updateAvailableDiskSpace(for url: URL) {
        let bytes = DiskSpaceMonitor.availableDiskSpace(at: url)
        availableDiskSpaceFormatted = DiskSpaceMonitor.formatBytes(bytes)
    }

    public func analyze(fileURL: URL) {
        state = .analyzing
        requiresPassword = false
        updateAvailableDiskSpace(for: fileURL)

        Task {
            do {
                let info = try ArchiveDetector.detect(mainFileURL: fileURL)
                guard info.type.format != .other else {
                    self.state = .failed(.unsupportedFormat("无法识别的压缩格式。支持 ZIP / RAR / 7Z / TAR / GZIP 及常见分卷"))
                    return
                }
                self.currentInfo = info
                // 加密预探测: 在展示确认页之前识别加密需求，避免破坏性解压启动后失败
                let probe = LibArchiveExtractor.probeEncryption(volumeURLs: info.volumeURLs, password: nil)
                self.encryptionProbe = probe
                self.requiresPassword = (probe == .passwordRequired)
                self.state = .ready(info)
            } catch let err as ExtractionError {
                self.state = .failed(err)
            } catch {
                self.state = .failed(.unknown(error.localizedDescription))
            }
        }
    }

    public func startExtraction(info: ArchiveInfo, password: String? = nil, chunkSizeMB: Int = 10) {
        let chunkSizeBytes = max(64 * 1024, chunkSizeMB * 1024 * 1024)
        self.currentInfo = info
        self.startTime = Date()
        self.lastTime = Date()
        self.lastBytes = 0

        self.state = .extracting(
            progress: 0.0,
            fileName: "准备解压...",
            processedSize: "0 MB",
            totalSize: info.formattedTotalSize,
            speed: "计算中..."
        )

        let probe = self.encryptionProbe
        extractionTask = Task.detached { [weak self] in
            let engine = self
            do {
                // 加密守卫: 需要密码但未提供时直接失败，交由 UI 收集后重新发起
                if case .passwordRequired = probe,
                   password == nil || password!.isEmpty {
                    await MainActor.run { engine?.state = .failed(.passwordRequired) }
                    return
                }

                let unrarAvailable = UnRARProcess.findUnRAR() != nil
                let preferUnrar: Bool
                switch probe {
                case .decoderUnsupported, .unknown:
                    preferUnrar = info.type.format == .rar && unrarAvailable
                default:
                    preferUnrar = false
                }
                if probe == .decoderUnsupported && !unrarAvailable {
                    await MainActor.run {
                        engine?.state = .failed(.encryptedDecoderUnsupported(formatName: info.type.format.rawValue))
                    }
                    return
                }

                func runUnrar(volumes: [URL]) async throws {
                    let unrar = UnRARProcess()
                    try await unrar.extractAndDelete(
                        mainVolume: info.mainVolumeURL,
                        volumes: volumes,
                        outputDirectory: info.outputDirectoryURL,
                        password: password
                    ) { progress in
                        Task { @MainActor in
                            engine?.handleProgress(progress)
                        }
                    }
                }

                switch info.type {
                case .single(let format):
                    if format == .rar && preferUnrar {
                        try await runUnrar(volumes: [info.mainVolumeURL])
                    } else {
                        let reader: ChunkReader
                        if format == .sevenZip {
                            // 7z 头信息位于尾部需要随机访问: APFS 上延迟到头部解析完成后打洞，
                            // 兼顾空间回收与随机读；非 APFS 无打洞可用，退回整体删除模式
                            if SpaceReclaimer.detectStrategy(for: info.mainVolumeURL) == .punchHole {
                                reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes,
                                                         strategy: .punchHole, punchAfterSeek: true)
                            } else {
                                reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes,
                                                         strategy: ReclaimStrategy.none)
                            }
                        } else {
                            reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes)
                        }
                        let extractor = LibArchiveExtractor()
                        try await extractor.extract(
                            source: reader,
                            to: info.outputDirectoryURL,
                            password: password
                        ) { progress in
                            Task { @MainActor in
                                engine?.handleProgress(progress)
                            }
                        }
                    }

                case .multiVolume(let format):
                    if format == .rar && (unrarAvailable || preferUnrar) {
                        try await runUnrar(volumes: info.volumeURLs)
                    } else {
                        // 分卷 ZIP / TAR 等使用 libarchive 链式流逐卷解压并删除
                        let chainReader = try VolumeChainReader(
                            volumes: info.volumeURLs,
                            chunkSize: chunkSizeBytes,
                            deletesVolumesAsRead: format != .sevenZip
                        )
                        let extractor = LibArchiveExtractor()
                        try await extractor.extract(
                            source: chainReader,
                            to: info.outputDirectoryURL,
                            password: password
                        ) { progress in
                            Task { @MainActor in
                                engine?.handleProgress(progress)
                            }
                        }
                    }
                }

                Task { @MainActor in
                    engine?.state = .completed(outputURL: info.outputDirectoryURL)
                    engine?.updateAvailableDiskSpace(for: info.outputDirectoryURL)
                }

            } catch is CancellationError {
                Task { @MainActor [weak self] in
                    self?.state = .cancelled
                }
            } catch let err as ExtractionError {
                Task { @MainActor [weak self] in
                    self?.state = .failed(err)
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.state = .failed(.unknown(error.localizedDescription))
                }
            }
        }
    }

    public func cancel() {
        extractionTask?.cancel()
        extractionTask = nil
        state = .cancelled
    }

    public func reset() {
        cancel()
        currentInfo = nil
        requiresPassword = false
        state = .idle
    }

    private func handleProgress(_ progress: ExtractionProgress) {
        let now = Date()
        var speedStr = ""
        if let last = lastTime, now.timeIntervalSince(last) >= 0.5 {
            let dt = now.timeIntervalSince(last)
            let db = progress.processedBytes > lastBytes ? progress.processedBytes - lastBytes : 0
            let bytesPerSec = Double(db) / dt
            speedStr = DiskSpaceMonitor.formatBytes(UInt64(bytesPerSec)) + "/s"
            self.lastTime = now
            self.lastBytes = progress.processedBytes
        }

        let processedStr = DiskSpaceMonitor.formatBytes(progress.processedBytes)
        let totalStr = DiskSpaceMonitor.formatBytes(progress.totalBytes)

        self.state = .extracting(
            progress: progress.progress,
            fileName: progress.currentFileName,
            processedSize: processedStr,
            totalSize: totalStr,
            speed: speedStr.isEmpty ? "处理中..." : speedStr
        )
    }
}
