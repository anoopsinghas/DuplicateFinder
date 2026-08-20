import Foundation

public struct FileEntry: Hashable, Codable, Sendable, Identifiable {
    public let url: URL
    public let size: Int64
    public let modifiedAt: Date?
    public let kind: MediaKind
    /// PhotoKit `PHAsset.localIdentifier` when this entry came from the photo library.
    /// nil for regular filesystem entries. iOS uses this for deletion via PHPhotoLibrary.
    public let assetIdentifier: String?

    public var id: URL { url }

    public var isPhotoAsset: Bool { assetIdentifier != nil }

    public init(url: URL, size: Int64, modifiedAt: Date?, kind: MediaKind, assetIdentifier: String? = nil) {
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
        self.kind = kind
        self.assetIdentifier = assetIdentifier
    }
}
