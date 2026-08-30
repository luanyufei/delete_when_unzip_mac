import Foundation

@main
struct VerificationRunner {

    static func log(_ msg: String) {
        print(msg)
        fflush(stdout)
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
        if actual != expected {
            log("❌ FAIL [\(line)]: Expected '\(expected)', got '\(actual)'. \(message)")
            exit(1)
        } else {
            log("  ✅ PASS [\(line)]: \(actual)")
        }
    }

    static func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
        if !condition {
            log("❌ FAIL [\(line)]: Condition is false. \(message)")
            exit(1)
        } else {
            log("  ✅ PASS [\(line)]: Condition verified.")
        }
    }

    static func main() {
        Task.detached {
            await runAllTests()
            fflush(stdout)
            fflush(stderr)
            exit(0)
        }
        dispatchMain()
    }

    static func runAllTests() async {
        log("========================================================")
        log(" Running DeleteWhenUnzip macOS Native Test Suite")
        log("========================================================")

        // 1. 测试基础名称提取
        log("\n🧪 Test 1: VolumeScanner BaseName Extraction")
        assertEqual(VolumeScanner.extractBaseName(from: "game.part1.rar"), "game")
        assertEqual(VolumeScanner.extractBaseName(from: "game.part01.rar"), "game")
        assertEqual(VolumeScanner.extractBaseName(from: "data.z01"), "data")
        assertEqual(VolumeScanner.extractBaseName(from: "archive.zip.001"), "archive")
        assertEqual(VolumeScanner.extractBaseName(from: "archive.zip"), "archive")
        assertEqual(VolumeScanner.extractBaseName(from: "music.tar.gz"), "music")
        assertEqual(VolumeScanner.extractBaseName(from: "video.7z.001"), "video")
        assertEqual(VolumeScanner.extractBaseName(from: "standalone.txt"), "standalone.txt")

        // 2. 测试编码智能检测
        log("\n🧪 Test 2: FileNameDecoder UTF-8 & C-String")
        let utf8String = "中文测试_test_archive_ファイル"
        utf8String.withCString { ptr in
            assertEqual(FileNameDecoder.decode(cString: ptr), utf8String)
        }

        // 3. 测试 APFS 空间回收策略检测
        log("\n🧪 Test 3: APFS SpaceReclaimer Strategy")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dwu_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let testFile = tempDir.appendingPathComponent("probe.bin")
        FileManager.default.createFile(atPath: testFile.path, contents: Data(repeating: 0x41, count: 1024))
        let strategy = SpaceReclaimer.detectStrategy(for: testFile)
        log("  ℹ️ Detected strategy for \(testFile.path): \(strategy)")
        assertTrue(strategy == .punchHole || strategy == .shiftTruncate)

        // 4. 端到端实测：创建 ZIP 压缩包 -> 流式解压 -> 验证源文件删除与目标文件正确性
        log("\n🧪 Test 4: End-to-End Stream Unzip & Progressive Delete")
        let sampleDir = tempDir.appendingPathComponent("sample_archive")
        try? FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let sampleTxt = sampleDir.appendingPathComponent("content.txt")
        let testPayload = "macOS Native Swift Delete When Unzip - 2026 APFS Hole Punching Test Data!"
        try? testPayload.write(to: sampleTxt, atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("sample.zip")
        let outputDir = tempDir.appendingPathComponent("sample_output")

        // 压缩
        let zipProcess = Process()
        zipProcess.currentDirectoryURL = sampleDir
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.arguments = ["-r", zipURL.path, "."]
        zipProcess.standardOutput = Pipe()
        zipProcess.standardError = Pipe()
        try? zipProcess.run()
        zipProcess.waitUntilExit()

        assertTrue(FileManager.default.fileExists(atPath: zipURL.path), "Zip archive created")

        // 格式自动探测
        let info = try! ArchiveDetector.detect(mainFileURL: zipURL)
        assertEqual(info.type.format, .zip)
        log("  ℹ️ Detected format: \(info.type.displayName), size: \(info.formattedTotalSize)")

        // 流式解压 + 删除
        let reader = try! ChunkReader.make(fileURL: zipURL, chunkSize: 512)
        let extractor = LibArchiveExtractor()
        var progressList: [Double] = []

        log("  🚀 Starting extraction...")
        do {
            try await extractor.extract(source: reader, to: outputDir) { progress in
                progressList.append(progress.progress)
                log("    ↳ Progress: \(Int(progress.progress * 100))% - file: \(progress.currentFileName)")
            }
            log("  ✨ Extraction finished.")
        } catch {
            log("❌ Extractor failed with error: \(error)")
            exit(1)
        }

        assertTrue(!progressList.isEmpty, "Received progress callbacks")
        assertEqual(progressList.last ?? 0, 1.0, "Progress reached 100%")

        // 验证源 zip 文件已被成功删除
        assertTrue(!FileManager.default.fileExists(atPath: zipURL.path), "Original ZIP file was deleted")

        // 验证目标解压文件存在且内容完全一致
        let extractedTxt = outputDir.appendingPathComponent("content.txt")
        assertTrue(FileManager.default.fileExists(atPath: extractedTxt.path), "Extracted file exists")
        let extractedContent = (try? String(contentsOf: extractedTxt, encoding: .utf8)) ?? ""
        assertEqual(extractedContent, testPayload, "Extracted content matches payload")

        log("\n========================================================")
        log("🎉 ALL TESTS PASSED SUCCESSFULLY!")
        log("========================================================")
    }
}
