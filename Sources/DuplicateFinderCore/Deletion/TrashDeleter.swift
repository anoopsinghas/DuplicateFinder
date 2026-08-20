import Foundation

public struct TrashResult: Sendable {
    public struct Failure: Sendable {
        public let url: URL
        public let error: String
    }
    public let trashed: [URL]
    public let failures: [Failure]
    public var trashedBytes: Int64
}

public struct TrashDeleter: Sendable {
    public init() {}

    /// Moves each URL to the user's Trash. Returns per-file success/failure so the caller
    /// can surface a report even if some items fail.
    public func trash(_ urls: [URL]) -> TrashResult {
        var trashed: [URL] = []
        var failures: [TrashResult.Failure] = []
        var bytes: Int64 = 0
        let fm = FileManager.default

        for url in urls {
            do {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    bytes &+= Int64(size)
                }
                var resulting: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resulting)
                trashed.append(url)
            } catch {
                failures.append(.init(url: url, error: (error as NSError).localizedDescription))
            }
        }

        return TrashResult(trashed: trashed, failures: failures, trashedBytes: bytes)
    }
}
