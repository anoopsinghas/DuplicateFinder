import Foundation

public struct DuplicateGroup: Identifiable, Codable, Sendable, Hashable {
    public let contentHash: String
    public let size: Int64
    public let files: [FileEntry]

    public var id: String { contentHash }

    public var count: Int { files.count }

    public var wastedBytes: Int64 { size * Int64(max(0, files.count - 1)) }

    public init(contentHash: String, size: Int64, files: [FileEntry]) {
        self.contentHash = contentHash
        self.size = size
        self.files = files
    }
}
