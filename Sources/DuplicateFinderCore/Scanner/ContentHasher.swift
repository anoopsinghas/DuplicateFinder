import Foundation
import CryptoKit

public enum HasherError: Error {
    case cannotOpen(URL)
}

public struct ContentHasher: Sendable {
    public static let defaultBufferSize = 1 << 20 // 1 MiB

    public let bufferSize: Int

    public init(bufferSize: Int = ContentHasher.defaultBufferSize) {
        self.bufferSize = bufferSize
    }

    public func sha256(of url: URL, bytesHashed: ((Int) -> Void)? = nil) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw HasherError.cannotOpen(url)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            if Task.isCancelled { break }
            let chunk = try handle.read(upToCount: bufferSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            bytesHashed?(chunk.count)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Chunk-fed SHA-256 for sources that aren't a `FileHandle` — e.g. PhotoKit's
/// `PHAssetResourceManager.requestData(for:)` which delivers bytes as `Data` blocks.
/// Not `Sendable`: the internal `SHA256` state must not cross concurrency boundaries.
public final class StreamingSHA256 {
    private var hasher = SHA256()
    private(set) public var bytesHashed: Int64 = 0

    public init() {}

    public func update(_ data: Data) {
        hasher.update(data: data)
        bytesHashed &+= Int64(data.count)
    }

    public func finalizeHex() -> String {
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
