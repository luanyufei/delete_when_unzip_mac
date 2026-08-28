import Foundation

public struct ArchiveInfo: Sendable, Identifiable {
    public var id: String { mainVolumeURL.path }

    public let type: ArchiveType
    public let mainVolumeURL: URL
    public let volumeURLs: [URL]
    public let baseName: String
    public let outputDirectoryURL: URL
    public let totalCompressedSize: UInt64
    public let formattedTotalSize: String

    public init(
        type: ArchiveType,
        mainVolumeURL: URL,
        volumeURLs: [URL],
        baseName: String,
        outputDirectoryURL: URL
    ) {
        self.type = type
        self.mainVolumeURL = mainVolumeURL
        self.volumeURLs = volumeURLs
        self.baseName = baseName
        self.outputDirectoryURL = outputDirectoryURL

        var totalSize: UInt64 = 0
        for url in volumeURLs {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                totalSize += size
            }
        }
        self.totalCompressedSize = totalSize
        self.formattedTotalSize = ByteCountFormatter.string(
            fromByteCount: Int64(totalSize),
            countStyle: .file
        )
    }
}
