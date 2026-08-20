import Foundation

public struct ScanProgress: Sendable {
    public enum Phase: String, Sendable {
        case walking
        case hashing
        case finalizing
        case done
        case cancelled
    }

    public let phase: Phase
    public let filesSeen: Int
    public let candidatesToHash: Int
    public let filesHashed: Int
    public let bytesHashed: Int64
    public let currentPath: String?

    public init(
        phase: Phase,
        filesSeen: Int,
        candidatesToHash: Int,
        filesHashed: Int,
        bytesHashed: Int64,
        currentPath: String?
    ) {
        self.phase = phase
        self.filesSeen = filesSeen
        self.candidatesToHash = candidatesToHash
        self.filesHashed = filesHashed
        self.bytesHashed = bytesHashed
        self.currentPath = currentPath
    }
}

public struct ScanResult: Sendable {
    public let groups: [DuplicateGroup]
    public let filesSeen: Int
    public let filesHashed: Int
    public let bytesHashed: Int64
    public let elapsedSeconds: Double

    public var totalWastedBytes: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    public init(groups: [DuplicateGroup], filesSeen: Int, filesHashed: Int, bytesHashed: Int64, elapsedSeconds: Double) {
        self.groups = groups
        self.filesSeen = filesSeen
        self.filesHashed = filesHashed
        self.bytesHashed = bytesHashed
        self.elapsedSeconds = elapsedSeconds
    }
}
