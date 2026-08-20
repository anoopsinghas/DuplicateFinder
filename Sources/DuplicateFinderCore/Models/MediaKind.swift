import Foundation

public enum MediaKind: String, CaseIterable, Codable, Sendable {
    case photo
    case video
    case document

    public var extensions: Set<String> {
        switch self {
        case .photo:
            return ["jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp",
                    "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2", "raf", "srw"]
        case .video:
            return ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "mpeg", "mpg", "3gp"]
        case .document:
            return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md",
                    "csv", "tsv", "odt", "ods", "odp", "epub"]
        }
    }

    public static func kind(forExtension ext: String) -> MediaKind? {
        let lower = ext.lowercased()
        for k in MediaKind.allCases where k.extensions.contains(lower) {
            return k
        }
        return nil
    }
}
