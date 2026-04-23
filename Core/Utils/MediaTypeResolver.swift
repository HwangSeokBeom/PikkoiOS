import Foundation

enum ResolvedMediaType: String, Sendable {
    case image
    case gif
    case video
    case pdf
    case unknown
}

enum MediaTypeResolver {
    static func resolve(from path: String) -> ResolvedMediaType {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()

        switch fileExtension {
        case "jpg", "jpeg", "png", "heic", "webp":
            return .image
        case "gif":
            return .gif
        case "mp4", "mov", "avi", "mkv", "wmv", "m4v":
            return .video
        case "pdf":
            return .pdf
        default:
            return .unknown
        }
    }

    static func mimeType(for path: String) -> String {
        switch resolve(from: path) {
        case .image:
            return "image/*"
        case .gif:
            return "image/gif"
        case .video:
            return "video/*"
        case .pdf:
            return "application/pdf"
        case .unknown:
            return "application/octet-stream"
        }
    }
}
