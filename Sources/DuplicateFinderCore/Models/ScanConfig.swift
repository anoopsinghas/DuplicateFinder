import Foundation

public struct ScanConfig: Sendable {
    public var roots: [URL]
    public var kinds: Set<MediaKind>
    public var minSize: Int64
    public var excludedDirectoryNames: Set<String>
    public var excludedPathSubstrings: Set<String>
    public var followSymlinks: Bool

    public init(
        roots: [URL],
        kinds: Set<MediaKind> = Set(MediaKind.allCases),
        minSize: Int64 = 1,
        excludedDirectoryNames: Set<String> = ScanConfig.defaultExcludedDirectoryNames,
        excludedPathSubstrings: Set<String> = ScanConfig.defaultExcludedPathSubstrings,
        followSymlinks: Bool = false
    ) {
        self.roots = roots
        self.kinds = kinds
        self.minSize = minSize
        self.excludedDirectoryNames = excludedDirectoryNames
        self.excludedPathSubstrings = excludedPathSubstrings
        self.followSymlinks = followSymlinks
    }

    public static let defaultExcludedDirectoryNames: Set<String> = [
        "Library", ".Trash", ".git", ".hg", ".svn",
        "node_modules", ".venv", "venv", "__pycache__",
        "Caches", ".cache", ".DS_Store",
        "DerivedData", ".build", ".swiftpm",
        ".idea", ".gradle", "target",
    ]

    public static let defaultExcludedPathSubstrings: Set<String> = [
        "/System/",
        "/private/var/folders/",
        "/private/var/db/",
        "/private/var/vm/",
    ]

    public static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "framework", "bundle", "xcodeproj", "xcworkspace",
        "playground",
    ]
}
