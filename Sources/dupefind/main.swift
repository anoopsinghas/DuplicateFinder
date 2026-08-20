import Foundation
import DuplicateFinderCore

// MARK: - CLI parsing

struct CLIOptions {
    var roots: [URL] = []
    var kinds: Set<MediaKind> = Set(MediaKind.allCases)
    var minSize: Int64 = 1
    var jsonOutput: Bool = false
    var listOnly: Bool = true       // default: just list dupes
    var trashPolicy: TrashPolicy?   // if set, we plan a delete
    var confirm: Bool = false       // required to actually trash
    var quiet: Bool = false

    enum TrashPolicy: String {
        case keepNewest = "keep-newest"
        case keepOldest = "keep-oldest"
        case keepFirstPath = "keep-first-path"
    }
}

func printUsage() {
    let text = """
    dupefind — find duplicate photos/videos/documents by SHA-256

    USAGE
      dupefind [OPTIONS] ROOT [ROOT ...]

    OPTIONS
      --kinds photo,video,document   Which media kinds to scan (default: all)
      --min-size BYTES               Skip files smaller than this (default: 1)
      --json                         Emit JSON instead of human-readable text
      --quiet                        Suppress progress lines
      --trash POLICY                 Plan deletion. POLICY = keep-newest | keep-oldest | keep-first-path
      --confirm                      Actually move files to Trash (default: dry-run)
      -h, --help                     Show this help

    EXAMPLES
      dupefind ~/Pictures ~/Downloads
      dupefind --kinds photo,video ~/Movies
      dupefind --trash keep-newest ~/Downloads           # dry-run: prints plan
      dupefind --trash keep-newest --confirm ~/Downloads # actually trashes
    """
    print(text)
}

func parseArgs(_ args: [String]) -> CLIOptions? {
    var opts = CLIOptions()
    var i = 1
    while i < args.count {
        let a = args[i]
        switch a {
        case "-h", "--help":
            return nil
        case "--kinds":
            i += 1
            guard i < args.count else { return nil }
            let parts = args[i].split(separator: ",").map { String($0) }
            var set: Set<MediaKind> = []
            for p in parts {
                guard let k = MediaKind(rawValue: p) else {
                    FileHandle.standardError.write(Data("unknown kind: \(p)\n".utf8))
                    return nil
                }
                set.insert(k)
            }
            opts.kinds = set
        case "--min-size":
            i += 1
            guard i < args.count, let n = Int64(args[i]) else { return nil }
            opts.minSize = n
        case "--json":
            opts.jsonOutput = true
        case "--quiet":
            opts.quiet = true
        case "--trash":
            i += 1
            guard i < args.count, let p = CLIOptions.TrashPolicy(rawValue: args[i]) else {
                FileHandle.standardError.write(Data("unknown --trash policy\n".utf8))
                return nil
            }
            opts.trashPolicy = p
            opts.listOnly = false
        case "--confirm":
            opts.confirm = true
        default:
            let url = URL(fileURLWithPath: (a as NSString).expandingTildeInPath).standardizedFileURL
            opts.roots.append(url)
        }
        i += 1
    }
    return opts.roots.isEmpty ? nil : opts
}

// MARK: - Formatting

func humanBytes(_ n: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = Double(n)
    var u = 0
    while v >= 1024 && u < units.count - 1 { v /= 1024; u += 1 }
    return String(format: v < 10 ? "%.2f %@" : "%.1f %@", v, units[u])
}

func filesToDeleteForGroup(_ g: DuplicateGroup, policy: CLIOptions.TrashPolicy) -> [FileEntry] {
    guard g.files.count >= 2 else { return [] }
    let sorted: [FileEntry]
    switch policy {
    case .keepNewest:
        sorted = g.files.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
    case .keepOldest:
        sorted = g.files.sorted { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
    case .keepFirstPath:
        sorted = g.files.sorted { $0.url.path < $1.url.path }
    }
    return Array(sorted.dropFirst())
}

// MARK: - Main

let args = CommandLine.arguments
guard let opts = parseArgs(args) else {
    printUsage()
    exit(args.count > 1 ? 1 : 0)
}

let config = ScanConfig(
    roots: opts.roots,
    kinds: opts.kinds,
    minSize: opts.minSize
)
let grouper = DuplicateGrouper(config: config)

var lastPrint = Date(timeIntervalSince1970: 0)
let result = grouper.scan { progress in
    if opts.quiet || opts.jsonOutput { return }
    let now = Date()
    if now.timeIntervalSince(lastPrint) < 0.1 && progress.phase != .done && progress.phase != .finalizing {
        return
    }
    lastPrint = now
    let line: String
    switch progress.phase {
    case .walking:
        line = "walking… \(progress.filesSeen) files"
    case .hashing:
        line = "hashing… \(progress.filesHashed)/\(progress.candidatesToHash) (\(humanBytes(progress.bytesHashed)))"
    case .finalizing:
        line = "finalizing…"
    case .done:
        line = "done."
    case .cancelled:
        line = "cancelled."
    }
    FileHandle.standardError.write(Data("\r\u{001B}[K\(line)".utf8))
    if progress.phase == .done || progress.phase == .cancelled {
        FileHandle.standardError.write(Data("\n".utf8))
    }
}

if opts.jsonOutput {
    struct OutFile: Encodable { let path: String; let size: Int64; let modifiedAt: Date? }
    struct OutGroup: Encodable { let hash: String; let size: Int64; let wastedBytes: Int64; let files: [OutFile] }
    struct Out: Encodable {
        let filesSeen: Int
        let filesHashed: Int
        let bytesHashed: Int64
        let elapsedSeconds: Double
        let totalWastedBytes: Int64
        let groups: [OutGroup]
    }
    let out = Out(
        filesSeen: result.filesSeen,
        filesHashed: result.filesHashed,
        bytesHashed: result.bytesHashed,
        elapsedSeconds: result.elapsedSeconds,
        totalWastedBytes: result.totalWastedBytes,
        groups: result.groups.map { g in
            OutGroup(hash: g.contentHash, size: g.size, wastedBytes: g.wastedBytes,
                     files: g.files.map { OutFile(path: $0.url.path, size: $0.size, modifiedAt: $0.modifiedAt) })
        }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(out), let s = String(data: data, encoding: .utf8) {
        print(s)
    }
} else {
    if result.groups.isEmpty {
        print("No duplicates found. Scanned \(result.filesSeen) files in \(String(format: "%.1fs", result.elapsedSeconds)).")
    } else {
        print("\nFound \(result.groups.count) duplicate group(s). Wasted: \(humanBytes(result.totalWastedBytes))")
        print("Scanned \(result.filesSeen) files, hashed \(result.filesHashed) (\(humanBytes(result.bytesHashed))) in \(String(format: "%.1fs", result.elapsedSeconds)).\n")
        for (idx, g) in result.groups.enumerated() {
            print("[\(idx + 1)] \(g.count) copies · \(humanBytes(g.size)) each · wastes \(humanBytes(g.wastedBytes))")
            print("    sha256: \(g.contentHash)")
            for f in g.files {
                let m = f.modifiedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "?"
                print("      \(f.url.path)   (mod \(m))")
            }
            print("")
        }
    }
}

// Deletion phase (opt-in via --trash)
if let policy = opts.trashPolicy {
    let plan: [(DuplicateGroup, [FileEntry])] = result.groups.map { g in (g, filesToDeleteForGroup(g, policy: policy)) }
    let allToDelete = plan.flatMap { $0.1 }
    let plannedBytes = allToDelete.reduce(Int64(0)) { $0 + $1.size }

    print("\n---\nTrash plan (policy: \(policy.rawValue)):")
    for (g, files) in plan where !files.isEmpty {
        print("  group \(g.contentHash.prefix(8)) · would delete \(files.count) of \(g.count):")
        for f in files { print("    - \(f.url.path)") }
    }
    print("Total: \(allToDelete.count) files, \(humanBytes(plannedBytes)) freed.")

    guard opts.confirm else {
        print("\nDry-run. Add --confirm to actually move these to Trash.")
        exit(0)
    }
    print("\nMoving to Trash…")
    let deleter = TrashDeleter()
    let tr = deleter.trash(allToDelete.map { $0.url })
    print("Trashed \(tr.trashed.count) files (\(humanBytes(tr.trashedBytes))).")
    if !tr.failures.isEmpty {
        print("Failures (\(tr.failures.count)):")
        for f in tr.failures { print("  - \(f.url.path): \(f.error)") }
        exit(2)
    }
}
