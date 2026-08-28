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

    private var extractionTask: Task<Void, Never>?
    private var startTime: Date?
    private var lastBytes: UInt64 = 0
    private var lastTime: Date?

    public init() {}

    public func updateAvailableDiskSpace(for url: URL) {
        let bytes = DiskSpaceMonitor.availableDiskSpace(at: url)
        availableDiskSpaceFormatted = DiskSpaceMonitor.formatBytes(bytes)
    }

    public func analyze(fileURL: URL) {
        state = .analyzing
        updateAvailableDiskSpace(for: fileURL)

        Task {
            do {
                let info = try ArchiveDetector.detect(mainFileURL: fileURL)
                self.currentInfo = info
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

        extractionTask = Task.detached { [weak self] in
            let engine = self
            do {
                switch info.type {
                case .single:
                    let reader = try ChunkReader(fileURL: info.mainVolumeURL, chunkSize: chunkSizeBytes)
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

                case .multiVolume(let format):
                    if format == .rar {
                        // 分卷 RAR 优先尝试使用 unrar 监控方案，如果无 unrar 则使用 libarchive 链式流
                        if UnRARProcess.findUnRAR() != nil {
                            let unrar = UnRARProcess()
                            try await unrar.extractAndDelete(
                                mainVolume: info.mainVolumeURL,
                                volumes: info.volumeURLs,
                                outputDirectory: info.outputDirectoryURL,
                                password: password
                            ) { progress in
                                Task { @MainActor in
                                    engine?.handleProgress(progress)
                                }
                            }
                        } else {
                            let chainReader = try VolumeChainReader(volumes: info.volumeURLs, chunkSize: chunkSizeBytes)
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
                    } else {
                        // 分卷 ZIP / TAR 等使用 libarchive 链式流逐卷解压并删除
                        let chainReader = try VolumeChainReader(volumes: info.volumeURLs, chunkSize: chunkSizeBytes)
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
