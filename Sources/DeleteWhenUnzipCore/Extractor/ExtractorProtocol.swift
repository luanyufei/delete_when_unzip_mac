import Foundation

public struct ExtractionProgress: Sendable {
    public let progress: Double             // 0.0 ~ 1.0
    public let currentFileName: String
    public let processedBytes: UInt64
    public let totalBytes: UInt64

    public init(progress: Double, currentFileName: String, processedBytes: UInt64, totalBytes: UInt64) {
        self.progress = progress
        self.currentFileName = currentFileName
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
    }
}

public protocol Extractor: Sendable {
    func extract(
        source: StreamDataSource,
        to outputDirectory: URL,
        password: String?,
        progressHandler: @escaping @Sendable (ExtractionProgress) -> Void
    ) async throws
}
