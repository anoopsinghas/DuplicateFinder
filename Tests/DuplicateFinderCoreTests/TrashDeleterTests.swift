import Foundation
import Testing
@testable import DuplicateFinderCore

@Suite("TrashDeleter")
struct TrashDeleterTests {
    @Test("moves file out of its original path")
    func trashRemovesOriginal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("trashme.txt")
        try Data("bye".utf8).write(to: a)
        #expect(FileManager.default.fileExists(atPath: a.path))

        let result = TrashDeleter().trash([a])
        #expect(result.trashed.count == 1)
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: a.path))
    }

    @Test("missing file reported as failure, not thrown")
    func missingFileReportedAsFailure() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ghost = dir.appendingPathComponent("does-not-exist.txt")

        let result = TrashDeleter().trash([ghost])
        #expect(result.trashed.isEmpty)
        #expect(result.failures.count == 1)
    }
}
