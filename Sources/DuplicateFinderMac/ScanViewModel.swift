import Foundation
import SwiftUI
import DuplicateFinderCore

@MainActor
final class ScanViewModel: ObservableObject {
    enum State { case idle, scanning, done }

    @Published var state: State = .idle

    // Config
    @Published var roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @Published var scanPhotos: Bool = true
    @Published var scanVideos: Bool = true
    @Published var scanDocuments: Bool = true
    @Published var minSizeBytes: Int64 = 1

    // Progress
    @Published var progress: ScanProgress = ScanProgress(
        phase: .walking, filesSeen: 0, candidatesToHash: 0,
        filesHashed: 0, bytesHashed: 0, currentPath: nil
    )

    // Result
    @Published var result: ScanResult?
    @Published var selection: Set<URL> = []

    // Trash outcome
    @Published var lastTrashResult: TrashResult?

    private var scanTask: Task<Void, Never>?

    var kinds: Set<MediaKind> {
        var s: Set<MediaKind> = []
        if scanPhotos { s.insert(.photo) }
        if scanVideos { s.insert(.video) }
        if scanDocuments { s.insert(.document) }
        return s
    }

    func addRoot(_ url: URL) {
        if !roots.contains(url) { roots.append(url) }
    }

    func removeRoots(atOffsets offsets: IndexSet) {
        roots.remove(atOffsets: offsets)
    }

    func startScan() {
        guard state != .scanning else { return }
        state = .scanning
        selection.removeAll()
        result = nil

        let cfg = ScanConfig(roots: roots, kinds: kinds, minSize: minSizeBytes)
        let grouper = DuplicateGrouper(config: cfg)

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let r = grouper.scan { p in
                Task { @MainActor [weak self] in
                    self?.progress = p
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.result = r
                self.state = .done
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func selectAllExceptFirst() {
        guard let result else { return }
        var set: Set<URL> = []
        for g in result.groups {
            for (i, f) in g.files.enumerated() where i > 0 {
                set.insert(f.url)
            }
        }
        selection = set
    }

    func keepNewestInAllGroups() {
        applyPerGroup { g in
            let sorted = g.files.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
            return Array(sorted.dropFirst()).map { $0.url }
        }
    }

    func keepOldestInAllGroups() {
        applyPerGroup { g in
            let sorted = g.files.sorted { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
            return Array(sorted.dropFirst()).map { $0.url }
        }
    }

    func clearSelection() { selection.removeAll() }

    private func applyPerGroup(_ pick: (DuplicateGroup) -> [URL]) {
        guard let result else { return }
        var s: Set<URL> = []
        for g in result.groups { s.formUnion(pick(g)) }
        selection = s
    }

    var selectedBytes: Int64 {
        guard let result else { return 0 }
        var sum: Int64 = 0
        for g in result.groups {
            for f in g.files where selection.contains(f.url) { sum &+= f.size }
        }
        return sum
    }

    /// Safety rail: every group must keep at least one file. Returns URLs that would
    /// leave a group empty if trashed.
    func groupsWithAllFilesSelected() -> [DuplicateGroup] {
        guard let result else { return [] }
        return result.groups.filter { g in g.files.allSatisfy { selection.contains($0.url) } }
    }

    func performTrash() {
        guard groupsWithAllFilesSelected().isEmpty else { return }
        let urls = Array(selection)
        let tr = TrashDeleter().trash(urls)
        lastTrashResult = tr

        // Drop trashed files from the result set so the UI updates.
        if let result {
            let trashedSet = Set(tr.trashed)
            let newGroups = result.groups.compactMap { g -> DuplicateGroup? in
                let remaining = g.files.filter { !trashedSet.contains($0.url) }
                return remaining.count >= 2 ? DuplicateGroup(contentHash: g.contentHash, size: g.size, files: remaining) : nil
            }
            self.result = ScanResult(
                groups: newGroups,
                filesSeen: result.filesSeen,
                filesHashed: result.filesHashed,
                bytesHashed: result.bytesHashed,
                elapsedSeconds: result.elapsedSeconds
            )
        }
        selection.removeAll()
    }
}
