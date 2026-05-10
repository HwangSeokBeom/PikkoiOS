import Foundation
import UniformTypeIdentifiers

enum FileUploadEndpointPolicy: Equatable, Sendable {
    case profileImage
    case chatFiles
    case postFiles
    case reviewImages

    var maxFileCount: Int {
        switch self {
        case .profileImage:
            return 1
        case .chatFiles, .postFiles, .reviewImages:
            return 5
        }
    }

    var maxFileSizeBytes: Int {
        switch self {
        case .profileImage:
            return 1 * 1024 * 1024
        case .chatFiles, .postFiles, .reviewImages:
            return 5 * 1024 * 1024
        }
    }

    var allowedExtensions: Set<String> {
        switch self {
        case .profileImage, .reviewImages:
            return ["jpg", "jpeg", "png"]
        case .chatFiles:
            return ["jpg", "jpeg", "png", "gif", "heic", "heif", "pdf"]
        case .postFiles:
            return ["jpg", "jpeg", "png", "gif", "webp", "mp4", "mov", "avi", "mkv", "wmv"]
        }
    }

    var allowedMimeTypes: Set<String> {
        switch self {
        case .profileImage, .reviewImages:
            return ["image/jpeg", "image/jpg", "image/png"]
        case .chatFiles:
            return ["image/jpeg", "image/jpg", "image/png", "image/gif", "image/heic", "image/heif", "application/pdf"]
        case .postFiles:
            return [
                "image/jpeg",
                "image/jpg",
                "image/png",
                "image/gif",
                "image/webp",
                "video/mp4",
                "video/quicktime",
                "video/x-msvideo",
                "video/x-matroska",
                "video/x-ms-wmv"
            ]
        }
    }

    var compressibleImageExtensions: Set<String> {
        ["jpg", "jpeg", "png"]
    }
}

enum FileUploadValidationError: Error, Equatable {
    case tooManyFiles(maxCount: Int)
    case emptyFile(fileName: String)
    case unsupportedType(fileName: String, allowedExtensions: [String])
    case fileTooLarge(fileName: String, maxBytes: Int)
}

extension FileUploadValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .tooManyFiles(let maxCount):
            return "첨부 파일은 최대 \(maxCount)개까지 업로드할 수 있어요."
        case .emptyFile:
            return "비어 있는 파일은 업로드할 수 없어요."
        case .unsupportedType(_, let extensions):
            return "지원하지 않는 파일 형식이에요. \(extensions.joined(separator: ", "))만 가능해요."
        case .fileTooLarge(_, let maxBytes):
            return "파일은 \(Self.megabyteText(maxBytes)) 이하만 업로드할 수 있어요."
        }
    }

    private static func megabyteText(_ bytes: Int) -> String {
        let megabytes = max(1, bytes / 1_024 / 1_024)
        return "\(megabytes)MB"
    }
}

struct FileUploadDescriptor: Equatable, Sendable {
    let fileName: String
    let normalizedExtension: String
    let normalizedMimeType: String
    let typeIdentifier: String?
    let policy: FileUploadEndpointPolicy

    var isSupported: Bool {
        extensionIsSupported && (mimeTypeIsSupported || utiIsSupported || typeIdentifier == nil)
    }

    var isCompressibleImage: Bool {
        policy.compressibleImageExtensions.contains(normalizedExtension)
            || normalizedMimeType == "image/jpeg"
            || normalizedMimeType == "image/jpg"
            || normalizedMimeType == "image/png"
            || normalizedMimeType == "image/heic"
            || normalizedMimeType == "image/heif"
            || conforms(to: .jpeg)
            || conforms(to: .png)
            || conforms(to: .heic)
            || conforms(to: .heif)
    }

    private var extensionIsSupported: Bool {
        guard !normalizedExtension.isEmpty else {
            return mimeTypeIsSupported || utiIsSupported
        }
        return policy.allowedExtensions.contains(normalizedExtension)
    }

    private var mimeTypeIsSupported: Bool {
        policy.allowedMimeTypes.contains(normalizedMimeType)
    }

    private var utiIsSupported: Bool {
        guard let typeIdentifier,
              let type = UTType(typeIdentifier) else {
            return false
        }

        switch policy {
        case .profileImage, .reviewImages:
            return type.conforms(to: .jpeg) || type.conforms(to: .png)
        case .chatFiles:
            return type.conforms(to: .jpeg)
                || type.conforms(to: .png)
                || type.conforms(to: .gif)
                || type.conforms(to: .heic)
                || type.conforms(to: .heif)
                || type.conforms(to: .pdf)
        case .postFiles:
            return type.conforms(to: .image) || type.conforms(to: .movie)
        }
    }

    private func conforms(to parent: UTType) -> Bool {
        guard let typeIdentifier,
              let type = UTType(typeIdentifier) else {
            return false
        }
        return type.conforms(to: parent)
    }
}

enum FileUploadValidator {
    static func validateFileCount(
        existingCount: Int = 0,
        incomingCount: Int,
        policy: FileUploadEndpointPolicy
    ) throws {
        guard incomingCount > 0 else { return }
        guard existingCount + incomingCount <= policy.maxFileCount else {
            throw FileUploadValidationError.tooManyFiles(maxCount: policy.maxFileCount)
        }
    }

    static func descriptor(
        fileName: String,
        mimeType: String,
        typeIdentifier: String?,
        policy: FileUploadEndpointPolicy
    ) throws -> FileUploadDescriptor {
        let descriptor = FileUploadDescriptor(
            fileName: fileName,
            normalizedExtension: (fileName as NSString).pathExtension.lowercased(),
            normalizedMimeType: mimeType.lowercased(),
            typeIdentifier: typeIdentifier,
            policy: policy
        )
        guard descriptor.isSupported else {
            throw FileUploadValidationError.unsupportedType(
                fileName: fileName,
                allowedExtensions: policy.allowedExtensions.sorted()
            )
        }
        return descriptor
    }

    static func validateSize(
        byteCount: Int,
        fileName: String,
        policy: FileUploadEndpointPolicy
    ) throws {
        guard byteCount > 0 else {
            throw FileUploadValidationError.emptyFile(fileName: fileName)
        }
        guard byteCount <= policy.maxFileSizeBytes else {
            throw FileUploadValidationError.fileTooLarge(
                fileName: fileName,
                maxBytes: policy.maxFileSizeBytes
            )
        }
    }
}
