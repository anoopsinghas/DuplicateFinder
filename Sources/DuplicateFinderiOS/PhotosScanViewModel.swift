import Foundation
import SwiftUI
import Photos
import DuplicateFinderCore

@MainActor
final class PhotosScanViewModel: ObservableObject {
    enum State { case idle, needsPermission, scanning, done }

    @Published var state: State = .idle
    @Published var includePhotos: Bool = true
    @Published var includeVideos: Bool = true

    @Published var progress: ScanProgress = ScanProgress(
        phase: .walking, filesSeen: 0, candidatesToHash: 0,
        filesHashed: 0, bytesHashed: 0, currentPath: nil
    )
    @Published var result: ScanResult?
    @Published var selection: Set<String> = []  // localIdentifiers
    @Published var lastDeleteResult: PhotoAssetDeleter.Result?
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    var kinds: Set<MediaKind> {
        var s: Set<MediaKind> = []
        if includePhotos { s.insert(.photo) }
        if includeVideos { s.insert(.video) }
        return s
    }

    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        state = (status == .authorized || status == .limited) ? .idle : .needsPermission
    }

    func requestAuthorization() async {
        let ok = await PhotoAssetEnumerator.requestAuthorization()
        state = ok ? .idle : .needsPermission
    }

    func startScan() {
        guard state == .idle else { return }
        state = .scanning
        selection.removeAll()
        result = nil
        errorMessage = nil

        let grouper = PhotoLibraryGrouper(kinds: kinds, minSize: 1)
        scanTask = Task { [weak self] in
            let r = await grouper.scan { p in
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

    func cancelScan() { scanTask?.cancel() }

    var selectedBytes: Int64 {
        guard let result else { return 0 }
        var sum: Int64 = 0
        for g in result.groups {
            for f in g.files where selection.contains(f.assetIdentifier ?? "") {
                sum &+= f.size
            }
        }
        return sum
    }

    func keepNewestInAllGroups() {
        applyPerGroup { g in
            let sorted = g.files.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
            return sorted.dropFirst().compactMap { $0.assetIdentifier }
        }
    }

    func keepOldestInAllGroups() {
        applyPerGroup { g in
            let sorted = g.files.sorted { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
            return sorted.dropFirst().compactMap { $0.assetIdentifier }
        }
    }

    func clearSelection() { selection.removeAll() }

    private func applyPerGroup(_ pick: (DuplicateGroup) -> [String]) {
        guard let result else { return }
        var s: Set<String> = []
        for g in result.groups { s.formUnion(pick(g)) }
        selection = s
    }

    func groupsWithAllFilesSelected() -> [DuplicateGroup] {
        guard let result else { return [] }
        return result.groups.filter { g in
            g.files.allSatisfy { selection.contains($0.assetIdentifier ?? "") }
        }
    }

    func performDelete() async {
        guard groupsWithAllFilesSelected().isEmpty else { return }
        let ids = Array(selection)

        var sizes: [String: Int64] = [:]
        if let result {
            for g in result.groups {
                for f in g.files {
                    if let id = f.assetIdentifier, selection.contains(id) {
                        sizes[id] = f.size
                    }
                }
            }
        }

        let r = await PhotoAssetDeleter().delete(identifiers: ids, sizesByIdentifier: sizes)
        lastDeleteResult = r

        if let result {
            let deletedSet = Set(r.deletedIdentifiers)
            let newGroups = result.groups.compactMap { g -> DuplicateGroup? in
                let remaining = g.files.filter { !deletedSet.contains($0.assetIdentifier ?? "") }
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

        if let err = r.error { errorMessage = err }
    }
}
