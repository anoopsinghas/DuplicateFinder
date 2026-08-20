import Foundation

public struct FileWalker: Sendable {
    public let config: ScanConfig

    public init(config: ScanConfig) {
        self.config = config
    }

    public func walk(
        onFileSeen: ((String) -> Void)? = nil
    ) -> [FileEntry] {
        var results: [FileEntry] = []
        var seenPaths = Set<String>()

        for root in config.roots {
            let expandedRoot = root.resolvingSymlinksInPath()
            walk(root: expandedRoot, results: &results, seen: &seenPaths, onFileSeen: onFileSeen)
        }
        return results
    }

    private func walk(
        root: URL,
        results: inout [FileEntry],
        seen: inout Set<String>,
        onFileSeen: ((String) -> Void)?
    ) {
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .fileSizeKey, .contentModificationDateKey, .nameKey,
        ]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        let rootPath = root.standardizedFileURL.path

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: options,
            errorHandler: { _, _ in true }
        ) else { return }

        while let obj = enumerator.nextObject() {
            if Task.isCancelled { return }
            guard let url = obj as? URL else { continue }

            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            let relPath = relativePath(of: url, under: rootPath)

            if shouldSkipDirectory(url: url, relativePath: relPath, values: values) {
                enumerator.skipDescendants()
                continue
            }

            guard values?.isRegularFile == true else { continue }
            if values?.isSymbolicLink == true { continue }
            if shouldSkipFile(relativePath: relPath) { continue }

            guard let size = values?.fileSize, Int64(size) >= config.minSize else { continue }
            guard let kind = MediaKind.kind(forExtension: url.pathExtension), config.kinds.contains(kind) else { continue }

            let path = url.standardizedFileURL.path
            if !seen.insert(path).inserted { continue }

            let entry = FileEntry(
                url: url,
                size: Int64(size),
                modifiedAt: values?.contentModificationDate,
                kind: kind
            )
            results.append(entry)
            onFileSeen?(path)
        }
    }

    private func relativePath(of url: URL, under rootPath: String) -> String {
        let p = url.standardizedFileURL.path
        if p.hasPrefix(rootPath) {
            let idx = p.index(p.startIndex, offsetBy: rootPath.count)
            let rel = String(p[idx...])
            return rel.hasPrefix("/") ? rel : "/" + rel
        }
        return p
    }

    private func shouldSkipDirectory(url: URL, relativePath: String, values: URLResourceValues?) -> Bool {
        let name = url.lastPathComponent
        if config.excludedDirectoryNames.contains(name) { return true }

        for sub in config.excludedPathSubstrings {
            if relativePath.contains(sub) { return true }
        }

        if values?.isDirectory == true {
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty && ScanConfig.packageExtensions.contains(ext) { return true }
            if values?.isPackage == true { return true }
        }
        return false
    }

    private func shouldSkipFile(relativePath: String) -> Bool {
        for sub in config.excludedPathSubstrings {
            if relativePath.contains(sub) { return true }
        }
        return false
    }
}
