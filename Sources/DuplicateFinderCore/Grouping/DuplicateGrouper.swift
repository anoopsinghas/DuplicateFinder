import Foundation

public struct DuplicateGrouper: Sendable {
    public let hasher: ContentHasher
    public let config: ScanConfig

    public init(config: ScanConfig, hasher: ContentHasher = ContentHasher()) {
        self.config = config
        self.hasher = hasher
    }

    /// Runs the full pipeline: walk → size prefilter → hash multi-file buckets → group.
    /// Publishes progress via the returned stream, and returns the ScanResult when done.
    public func scan(
        onProgress: ((ScanProgress) -> Void)? = nil
    ) -> ScanResult {
        let startedAt = ProcessInfo.processInfo.systemUptime

        let walker = FileWalker(config: config)
        var filesSeen = 0
        let entries = walker.walk(onFileSeen: { path in
            filesSeen += 1
            onProgress?(ScanProgress(
                phase: .walking,
                filesSeen: filesSeen,
                candidatesToHash: 0,
                filesHashed: 0,
                bytesHashed: 0,
                currentPath: path
            ))
        })

        if Task.isCancelled {
            return ScanResult(groups: [], filesSeen: filesSeen, filesHashed: 0, bytesHashed: 0,
                              elapsedSeconds: ProcessInfo.processInfo.systemUptime - startedAt)
        }

        // Bucket by size; only sizes with >= 2 entries are candidates.
        var bySize: [Int64: [FileEntry]] = [:]
        for e in entries {
            bySize[e.size, default: []].append(e)
        }
        let candidateBuckets = bySize.values.filter { $0.count >= 2 }
        let candidates = candidateBuckets.flatMap { $0 }

        var filesHashed = 0
        var bytesHashed: Int64 = 0

        // Hash each candidate.
        var byHash: [String: [FileEntry]] = [:]
        for bucket in candidateBuckets {
            if Task.isCancelled { break }
            for entry in bucket {
                if Task.isCancelled { break }
                onProgress?(ScanProgress(
                    phase: .hashing,
                    filesSeen: filesSeen,
                    candidatesToHash: candidates.count,
                    filesHashed: filesHashed,
                    bytesHashed: bytesHashed,
                    currentPath: entry.url.path
                ))
                do {
                    let hash = try hasher.sha256(of: entry.url, bytesHashed: { n in
                        bytesHashed &+= Int64(n)
                    })
                    byHash[hash, default: []].append(entry)
                } catch {
                    // Skip unreadable files silently — they can't be duplicates we can act on.
                }
                filesHashed += 1
            }
        }

        onProgress?(ScanProgress(
            phase: .finalizing,
            filesSeen: filesSeen,
            candidatesToHash: candidates.count,
            filesHashed: filesHashed,
            bytesHashed: bytesHashed,
            currentPath: nil
        ))

        let groups: [DuplicateGroup] = byHash.compactMap { (hash, files) in
            guard files.count >= 2, let size = files.first?.size else { return nil }
            let sorted = files.sorted { $0.url.path < $1.url.path }
            return DuplicateGroup(contentHash: hash, size: size, files: sorted)
        }.sorted { $0.wastedBytes > $1.wastedBytes }

        let phase: ScanProgress.Phase = Task.isCancelled ? .cancelled : .done
        onProgress?(ScanProgress(
            phase: phase,
            filesSeen: filesSeen,
            candidatesToHash: candidates.count,
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
