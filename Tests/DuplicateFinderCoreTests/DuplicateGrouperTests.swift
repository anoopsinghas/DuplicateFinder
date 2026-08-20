import Foundation
import Testing
@testable import DuplicateFinderCore

@Suite("DuplicateGrouper")
struct DuplicateGrouperTests {
    @Test("finds exact-content dupes and ignores uniques")
    func basicGrouping() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("photoA".utf8).write(to: dir.appendingPathComponent("a1.jpg"))
        try Data("photoA".utf8).write(to: dir.appendingPathComponent("a2.jpg"))

        let sub = dir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("docB".utf8).write(to: sub.appendingPathComponent("b1.txt"))
        try Data("docB".utf8).write(to: sub.appendingPathComponent("b2.txt"))
        try Data("docB".utf8).write(to: sub.appendingPathComponent("b3.txt"))

        try Data("uniquePhoto".utf8).write(to: dir.appendingPathComponent("solo.png"))
        try Data("uniqueDoc".utf8).write(to: dir.appendingPathComponent("solo.pdf"))

        // Same size, different content — must NOT group.
        try Data("aaaa".utf8).write(to: dir.appendingPathComponent("s4a.txt"))
        try Data("bbbb".utf8).write(to: dir.appendingPathComponent("s4b.txt"))

        let result = DuplicateGrouper(config: ScanConfig(roots: [dir])).scan()
        #expect(result.groups.count == 2)
        #expect(result.groups.map(\.count).sorted() == [2, 3])
    }

    @Test("kinds filter narrows to requested media types")
    func kindsFilter() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.jpg"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("b.jpg"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.pdf"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("b.pdf"))

        let result = DuplicateGrouper(config: ScanConfig(roots: [dir], kinds: [.photo])).scan()
        #expect(result.groups.count == 1)
        #expect(result.groups.first?.files.first?.kind == .photo)
    }

    @Test("excludes .git and Library descendants")
    func excludeRules() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let git = dir.appendingPathComponent(".git")
        let lib = dir.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: git.appendingPathComponent("a.jpg"))
        try Data("x".utf8).write(to: git.appendingPathComponent("b.jpg"))
        try Data("x".utf8).write(to: lib.appendingPathComponent("a.jpg"))
        try Data("x".utf8).write(to: lib.appendingPathComponent("b.jpg"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("keep1.jpg"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("keep2.jpg"))

        let result = DuplicateGrouper(config: ScanConfig(roots: [dir])).scan()
        #expect(result.groups.count == 1)
        #expect(result.groups.first?.files.count == 2)
        for f in result.groups.first?.files ?? [] {
            #expect(!f.url.path.contains("/.git/"))
            #expect(!f.url.path.contains("/Library/"))
        }
    }

    @Test("reports walking, hashing, and done phases")
    func progressPhases() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.jpg"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("b.jpg"))

        var phases: Set<ScanProgress.Phase> = []
        _ = DuplicateGrouper(config: ScanConfig(roots: [dir])).scan { phases.insert($0.phase) }
        #expect(phases.contains(.walking))
        #expect(phases.contains(.hashing))
        #expect(phases.contains(.done))
    }

    @Test("minSize skips small files even if duplicated")
    func minSizeFilter() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("tiny".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try Data("tiny".utf8).write(to: dir.appendingPathComponent("b.txt"))

        let result = DuplicateGrouper(config: ScanConfig(roots: [dir], minSize: 1024)).scan()
        #expect(result.groups.isEmpty)
    }
}
