import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ProcessedProfileImage: Equatable, Sendable {
    let data: Data
    let mimeType: String
    let fileExtension: String
    let filename: String
    let pixelSize: CGSize
    let originalPixelSize: CGSize
    let sourceFormat: String
    let originalUTI: String
    let originalMimeType: String
    let orientation: String
    let byteSize: Int
    let originalBytes: Int
    let compressionQuality: CGFloat
    let didDownsample: Bool

    var isUnderLimit: Bool {
        byteSize <= ProfileImagePreprocessor.maxBytes
    }
}

struct ProfileImagePreprocessResult: Equatable, Sendable {
    let data: Data
    let fileName: String
    let mimeType: String
    let fileExtension: String
    let pixelSize: CGSize
    let originalPixelSize: CGSize
    let sourceFormat: String
    let originalUTI: String
    let originalMimeType: String
    let orientation: String
    let originalBytes: Int
    let compressionQuality: CGFloat
    let didDownsample: Bool

    var isUnderLimit: Bool {
        data.count <= ProfileImagePreprocessor.maxBytes
    }

    init(processedImage: ProcessedProfileImage) {
        self.data = processedImage.data
        self.fileName = processedImage.filename
        self.mimeType = processedImage.mimeType
        self.fileExtension = processedImage.fileExtension
        self.pixelSize = processedImage.pixelSize
        self.originalPixelSize = processedImage.originalPixelSize
        self.sourceFormat = processedImage.sourceFormat
        self.originalUTI = processedImage.originalUTI
        self.originalMimeType = processedImage.originalMimeType
        self.orientation = processedImage.orientation
        self.originalBytes = processedImage.originalBytes
        self.compressionQuality = processedImage.compressionQuality
        self.didDownsample = processedImage.didDownsample
    }
}

enum ProfileImagePreprocessorError: Error, Equatable {
    case invalidImage
    case exceedsLimit
}

extension ProfileImagePreprocessorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "지원하지 않는 이미지 형식이에요. 다른 사진을 선택해 주세요."
        case .exceedsLimit:
            return "이미지 용량이 너무 커서 자동으로 줄였지만 업로드에 실패했어요. 다른 사진을 선택해 주세요."
        }
    }
}

struct ProfileImagePreprocessor {
    static let maxBytes: Int = 1 * 1024 * 1024
    static let targetBytes: Int = 900 * 1024
    private let preprocessor = ImageUploadPreprocessor(maxInitialPixel: 1_024)

    func processForProfileUpload(data: Data, originalFileName: String) async throws -> ProfileImagePreprocessResult {
        try await Task.detached(priority: .userInitiated) {
            try process(data: data, originalFileName: originalFileName)
        }.value
    }

    func process(data: Data, originalFileName: String) throws -> ProfileImagePreprocessResult {
        ProfileImagePreprocessResult(processedImage: try processImage(data: data, originalFileName: originalFileName))
    }

    func processImage(data: Data, originalFileName: String) throws -> ProcessedProfileImage {
        guard !data.isEmpty else {
            throw ProfileImagePreprocessorError.invalidImage
        }

        do {
            let sourceMetadata = Self.sourceMetadata(data: data, filename: originalFileName)
            let output = try preprocessor.process(
                ImageUploadPreprocessInput(
                    data: data,
                    filename: originalFileName,
                    mimeType: mimeType(from: originalFileName),
                    purpose: .profile,
                    targetLimitBytes: Self.targetBytes
                )
            )
            return ProcessedProfileImage(
                data: output.data,
                mimeType: "image/jpeg",
                fileExtension: "jpg",
                filename: "profile.jpg",
                pixelSize: CGSize(width: output.width, height: output.height),
                originalPixelSize: sourceMetadata.size,
                sourceFormat: sourceMetadata.format,
                originalUTI: sourceMetadata.uti,
                originalMimeType: sourceMetadata.mimeType,
                orientation: sourceMetadata.orientation,
                byteSize: output.data.count,
                originalBytes: data.count,
                compressionQuality: output.compressionQuality,
                didDownsample: output.didDownsample
            )
        } catch ImageUploadPreprocessorError.unsupportedType,
                ImageUploadPreprocessorError.cannotEncode {
            throw ProfileImagePreprocessorError.invalidImage
        } catch {
            throw ProfileImagePreprocessorError.exceedsLimit
        }
    }

    private func mimeType(from filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png":
            return "image/png"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        default:
            return "image/jpeg"
        }
    }

    private static func sourceMetadata(data: Data, filename: String) -> (size: CGSize, format: String, uti: String, mimeType: String, orientation: String) {
        let fallbackExtension = (filename as NSString).pathExtension.lowercased()
        let fallbackFormat = fallbackExtension.isEmpty ? "unknown" : fallbackExtension
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return (.zero, fallbackFormat, "unknown", "unknown", "unknown")
        }

        let typeIdentifier = CGImageSourceGetType(source) as String?
        let sourceType = typeIdentifier.flatMap { UTType($0) }
        let format = sourceType?.preferredFilenameExtension ?? fallbackFormat
        let mimeType = sourceType?.preferredMIMEType ?? "unknown"
        let uti = typeIdentifier ?? "unknown"
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (.zero, format, uti, mimeType, "unknown")
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let orientationValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
        return (
            CGSize(width: width, height: height),
            format,
            uti,
            mimeType,
            orientationValue.map(String.init) ?? "unknown"
        )
    }
}
