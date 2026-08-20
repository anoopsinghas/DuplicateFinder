import Foundation

#if canImport(Photos)
import Photos

/// Enumerates photo/video assets from the system Photos library and produces
/// `FileEntry` values whose `assetIdentifier` is the `PHAsset.localIdentifier`.
///
/// The URL on each entry is synthetic — `photolib://<localIdentifier>` — used only
/// as a stable, unique identity in `DuplicateGroup` and the UI. Actual bytes are
/// materialized on demand via `hash(asset:)` for streaming SHA-256.
public struct PhotoAssetEnumerator {
    public let kinds: Set<MediaKind>
    public let minSize: Int64

    public init(kinds: Set<MediaKind> = [.photo, .video], minSize: Int64 = 1) {
        self.kinds = kinds
        self.minSize = minSize
    }

    /// Requests the user's Photos permission if not yet granted. Returns true on
    /// full-access (`.authorized`) or limited access (`.limited`).
    @MainActor
    public static func requestAuthorization() async -> Bool {
        let level: PHAccessLevel = .readWrite
        let current = PHPhotoLibrary.authorizationStatus(for: level)
        if current == .authorized || current == .limited { return true }
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: level) { cont.resume(returning: $0) }
        }
        return granted == .authorized || granted == .limited
    }

    /// Enumerates all assets matching `kinds`, returning lightweight FileEntry
    /// records. Sizes come from the largest `PHAssetResource` for each asset.
    /// Callers still need to hash content to detect true duplicates.
    public func enumerateAssets(onSeen: ((FileEntry) -> Void)? = nil) -> [(FileEntry, PHAsset)] {
        var out: [(FileEntry, PHAsset)] = []

        var mediaTypes: [PHAssetMediaType] = []
        if kinds.contains(.photo) { mediaTypes.append(.image) }
        if kinds.contains(.video) { mediaTypes.append(.video) }
        guard !mediaTypes.isEmpty else { return [] }

        let fetch = PHFetchOptions()
        // Only assets that actually live on this device (not iCloud placeholders we can't hash locally).
        fetch.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        for type in mediaTypes {
            if Task.isCancelled { break }
            let result = PHAsset.fetchAssets(with: type, options: fetch)
            result.enumerateObjects { asset, _, stop in
                if Task.isCancelled { stop.pointee = true; return }
                guard let (size, ext) = Self.primarySizeAndExt(for: asset) else { return }
                if size < self.minSize { return }
                let kind: MediaKind = (type == .image) ? .photo : .video
                let synthetic = URL(string: "photolib://\(asset.localIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? asset.localIdentifier)/asset.\(ext)")!
                let entry = FileEntry(
                    url: synthetic,
                    size: size,
                    modifiedAt: asset.modificationDate ?? asset.creationDate,
                    kind: kind,
                    assetIdentifier: asset.localIdentifier
                )
                out.append((entry, asset))
                onSeen?(entry)
            }
        }
        return out
    }

    /// Streams the asset's bytes into a running SHA-256, returning the hex digest.
    /// Uses `PHAssetResourceManager` with `requestData(for:...)` so we never load the whole file.
    public func hash(asset: PHAsset, bytesHashed: ((Int) -> Void)? = nil) async throws -> String {
        guard let resource = Self.primaryResource(for: asset) else {
            throw HasherError.cannotOpen(URL(string: "photolib://\(asset.localIdentifier)")!)
        }
        let hasher = StreamingSHA256()
        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: opts,
                dataReceivedHandler: { chunk in
                    hasher.update(chunk)
                    bytesHashed?(chunk.count)
                },
                completionHandler: { error in
                    if let error = error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            )
        }
        return hasher.finalizeHex()
    }

    /// Returns (byteCount, fileExtension) for the largest resource on an asset.
    private static func primarySizeAndExt(for asset: PHAsset) -> (Int64, String)? {
        guard let resource = primaryResource(for: asset) else { return nil }
        let sizeAny = resource.value(forKey: "fileSize")
        let size = (sizeAny as? Int64) ?? Int64(sizeAny as? Int ?? 0)
        guard size > 0 else { return nil }
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        return (size, ext.isEmpty ? "bin" : ext)
    }

    private static func primaryResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        // Prefer the original photo/video over adjustments/edits.
        let preferred: [PHAssetResourceType] = [.photo, .video, .fullSizePhoto, .fullSizeVideo]
        for type in preferred {
            if let r = resources.first(where: { $0.type == type }) { return r }
        }
        return resources.first
    }
}
#endif
