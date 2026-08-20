import Foundation

#if canImport(Photos)
import Photos

/// Two-pass duplicate detection over PHAssets: enumerate → size prefilter → SHA-256.
/// Mirrors `DuplicateGrouper` but sources bytes from PhotoKit instead of the filesystem.
public struct PhotoLibraryGrouper {
    public let enumerator: PhotoAssetEnumerator

    public init(kinds: Set<MediaKind> = [.photo, .video], minSize: Int64 = 1) {
        self.enumerator = PhotoAssetEnumerator(kinds: kinds, minSize: minSize)
    }

    public func scan(
        onProgress: ((ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        let startedAt = ProcessInfo.processInfo.systemUptime

        var filesSeen = 0
        let assets = enumerator.enumerateAssets { entry in
            filesSeen += 1
            onProgress?(ScanProgress(
                phase: .walking,
                filesSeen: filesSeen,
                candidatesToHash: 0,
                filesHashed: 0,
                bytesHashed: 0,
                currentPath: entry.url.absoluteString
            ))
        }

        if Task.isCancelled {
            return ScanResult(groups: [], filesSeen: filesSeen, filesHashed: 0, bytesHashed: 0,
                              elapsedSeconds: ProcessInfo.processInfo.systemUptime - startedAt)
        }

        // Size prefilter.
        var bySize: [Int64: [(FileEntry, PHAsset)]] = [:]
        for pair in assets { bySize[pair.0.size, default: []].append(pair) }
        let candidateBuckets = bySize.values.filter { $0.count >= 2 }
        let candidateCount = candidateBuckets.reduce(0) { $0 + $1.count }

        var filesHashed = 0
        var bytesHashed: Int64 = 0
        var byHash: [String: [FileEntry]] = [:]

        for bucket in candidateBuckets {
            if Task.isCancelled { break }
            for (entry, asset) in bucket {
                if Task.isCancelled { break }
                onProgress?(ScanProgress(
                    phase: .hashing,
                    filesSeen: filesSeen,
                    candidatesToHash: candidateCount,
                    filesHashed: filesHashed,
                    bytesHashed: bytesHashed,
                    currentPath: entry.url.absoluteString
                ))
                do {
                    let hash = try await enumerator.hash(asset: asset, bytesHashed: { n in
                        bytesHashed &+= Int64(n)
                    })
                    byHash[hash, default: []].append(entry)
                } catch {
                    // Unreadable asset — skip it. Common causes: iCloud download failed, corrupt resource.
                }
                filesHashed += 1
            }
        }

        onProgress?(ScanProgress(
            phase: .finalizing,
            filesSeen: filesSeen,
            candidatesToHash: candidateCount,
            filesHashed: filesHashed,
            bytesHashed: bytesHashed,
            currentPath: nil
        ))

        let groups: [DuplicateGroup] = byHash.compactMap { (hash, files) in
            guard files.count >= 2, let size = files.first?.size else { return nil }
            let sorted = files.sorted { ($0.modifiedAt ?? .distantPast) < ($1.modifiedAt ?? .distantPast) }
            return DuplicateGroup(contentHash: hash, size: size, files: sorted)
        }.sorted { $0.wastedBytes > $1.wastedBytes }

        let phase: ScanProgress.Phase = Task.isCancelled ? .cancelled : .done
        onProgress?(ScanProgress(
            phase: phase,
            filesSeen: filesSeen,
            candidatesToHash: candidateCount,
            filesHashed: filesHashed,
            bytesHashed: bytesHashed,
            currentPath: nil
        ))

        return ScanResult(
            groups: groups,
            filesSeen: filesSeen,
            filesHashed: filesHashed,
            bytesHashed: bytesHashed,
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - startedAt
        )
    }
}
#endif
