import XCTest
@testable import DeleteWhenUnzipCore

final class DeleteWhenUnzipCoreTests: XCTestCase {

    func testExtractBaseName() {
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "game.part1.rar"), "game")
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "game.part01.rar"), "game")
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "data.z01"), "data")
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "archive.zip.001"), "archive")
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "archive.zip"), "archive")
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "music.tar.gz"), "music")
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "video.7z.001"), "video")
        XCTAssertEqual(VolumeScanner.extractBaseName(from: "simple_file.txt"), "simple_file.txt")
    }

    func testFileNameDecoder() {
        // UTF-8
        let utf8String = "测试文件_test.txt"
        utf8String.withCString { ptr in
            XCTAssertEqual(FileNameDecoder.decode(cString: ptr), utf8String)
        }
    }

    func testSpaceReclaimerStrategy() {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_strategy_\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: testFile.path, contents: Data(repeating: 0x41, count: 1024))
        defer { try? FileManager.default.removeItem(at: testFile) }

        let strategy = SpaceReclaimer.detectStrategy(for: testFile)
        // macOS 内置卷通常是 APFS
        XCTAssertTrue(strategy == .punchHole || strategy == .shiftTruncate)
    }

    func testSingleZipExtractionWithDelete() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 构造一个测试 zip 文件
        let zipURL = tempDir.appendingPathComponent("sample.zip")
        let outputDir = tempDir.appendingPathComponent("sample_output")

        // 使用 /usr/bin/zip 创建测试压缩包
        let testDoc = tempDir.appendingPathComponent("hello.txt")
        try "Hello Native macOS Swift Unzip!".write(to: testDoc, atomically: true, encoding: .utf8)

        let process = Process()
        process.currentDirectoryURL = tempDir
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["sample.zip", "hello.txt"]
        try process.run()
        process.waitUntilExit()

        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        // 执行流式解压与删除
        let reader = try ChunkReader(fileURL: zipURL, chunkSize: 1024)
        let extractor = LibArchiveExtractor()
        try await extractor.extract(source: reader, to: outputDir) { progress in
            XCTAssertGreaterThanOrEqual(progress.progress, 0.0)
        }

        // 验证源 zip 文件已被删除
        XCTAssertFalse(FileManager.default.fileExists(atPath: zipURL.path))

        // 验证目标解压文件存在且内容正确
        let extractedFile = outputDir.appendingPathComponent("hello.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
        let content = try String(contentsOf: extractedFile, encoding: .utf8)
        XCTAssertEqual(content, "Hello Native macOS Swift Unzip!")
    }
}
