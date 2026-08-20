import Foundation

#if canImport(Photos)
import Photos

/// Deletes PhotoKit assets by localIdentifier. Files land in Photos' "Recently Deleted"
/// album for 30 days, so the operation is reversible from the Photos app.
public struct PhotoAssetDeleter: Sendable {
    public struct Result: Sendable {
        public let deletedIdentifiers: [String]
        public let deletedBytes: Int64
        public let error: String?
    }

    public init() {}

    /// `sizesByIdentifier` is optional — used to report `deletedBytes` accurately.
    /// PHPhotoLibrary shows the system's own confirm-delete sheet automatically.
    public func delete(identifiers: [String], sizesByIdentifier: [String: Int64] = [:]) async -> Result {
        guard !identifiers.isEmpty else {
            return Result(deletedIdentifiers: [], deletedBytes: 0, error: nil)
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var found: [String] = []
        assets.enumerateObjects { asset, _, _ in found.append(asset.localIdentifier) }
        let bytes = found.reduce(Int64(0)) { $0 + (sizesByIdentifier[$1] ?? 0) }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return Result(deletedIdentifiers: found, deletedBytes: bytes, error: nil)
        } catch {
            return Result(deletedIdentifiers: [], deletedBytes: 0, error: (error as NSError).localizedDescription)
        }
    }
}
#endif
