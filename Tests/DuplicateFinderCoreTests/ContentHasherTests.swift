import Foundation
import Testing
@testable import DuplicateFinderCore

@Suite("ContentHasher")
struct ContentHasherTests {
    @Test("sha256 of empty file matches known vector")
    func emptyFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("empty.txt")
        try Data().write(to: f)

        let hash = try ContentHasher().sha256(of: f)
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("sha256 of 'hello world' matches known vector")
    func helloWorld() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("hw.txt")
        try Data("hello world".utf8).write(to: f)

        let hash = try ContentHasher().sha256(of: f)
        #expect(hash == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    @Test("streaming buffer size does not change result on multi-buffer file")
    func streamingConsistency() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("big.bin")

        // 5 MiB of a repeated pattern crosses several 1 MiB buffers.
        FileManager.default.createFile(atPath: f.path, contents: nil)
        let handle = try FileHandle(forWritingTo: f)
        let chunk = Data(repeating: 0xAB, count: 128 * 1024)
        for _ in 0..<40 { try handle.write(contentsOf: chunk) }
        try handle.close()

        let small = try ContentHasher(bufferSize: 4096).sha256(of: f)
        let large = try ContentHasher(bufferSize: 1 << 20).sha256(of: f)
        #expect(small == large)
    }
}

func makeTempDir() throws -> URL {
    let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("dftest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}
