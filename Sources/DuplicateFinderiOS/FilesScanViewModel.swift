import Foundation
import SwiftUI
import DuplicateFinderCore

@MainActor
final class FilesScanViewModel: ObservableObject {
    enum State { case idle, scanning, done }

    @Published var state: State = .idle
    @Published var rootURL: URL?
    @Published var scanPhotos: Bool = true
    @Published var scanVideos: Bool = true
    @Published var scanDocuments: Bool = true

    @Published var progress: ScanProgress = ScanProgress(
        phase: .walking, filesSeen: 0, candidatesToHash: 0,
        filesHashed: 0, bytesHashed: 0, currentPath: nil
    )
    @Published var result: ScanResult?
    @Published var selection: Set<URL> = []
    @Published var lastTrashResult: TrashResult?

    private var scanTask: Task<Void, Never>?

    var kinds: Set<MediaKind> {
        var s: Set<MediaKind> = []
        if scanPhotos { s.insert(.photo) }
        if scanVideos { s.insert(.video) }
        if scanDocuments { s.insert(.document) }
        return s
    }

    func startScan() {
        guard let root = rootURL, state != .scanning else { return }
        state = .scanning
        selection.removeAll()
        result = nil

        // The URL from UIDocumentPicker is security-scoped — must start/stop access.
        let scoped = root.startAccessingSecurityScopedResource()

        let cfg = ScanConfig(roots: [root], kinds: kinds, minSize: 1,
                             excludedDirectoryNames: [], excludedPathSubstrings: [])
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
                if scoped { root.stopAccessingSecurityScopedResource() }
            }
        }
    }

    func cancelScan() { scanTask?.cancel() }

    var selectedBytes: Int64 {
        guard let result else { return 0 }
        var sum: Int64 = 0
        for g in result.groups {
            for f in g.files where selection.contains(f.url) { sum &+= f.size }
        }
        return sum
    }

    func keepNewestInAllGroups() {
        applyPerGroup { g in
            let sorted = g.files.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
            return sorted.dropFirst().map { $0.url }
        }
    }

    func clearSelection() { selection.removeAll() }

    private func applyPerGroup(_ pick: (DuplicateGroup) -> [URL]) {
        guard let result else { return }
        var s: Set<URL> = []
        for g in result.groups { s.formUnion(pick(g)) }
        selection = s
    }

    func groupsWithAllFilesSelected() -> [DuplicateGroup] {
        guard let result else { return [] }
        return result.groups.filter { g in g.files.allSatisfy { selection.contains($0.url) } }
    }

    func performTrash() {
        guard groupsWithAllFilesSelected().isEmpty, let root = rootURL else { return }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }

        let urls = Array(selection)
        let tr = TrashDeleter().trash(urls)
        lastTrashResult = tr

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
