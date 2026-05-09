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
    case unsupportedFormat
    case decodeFailed
    case compressionFailed
    case fileTooLargeAfterCompression
}

extension ProfileImagePreprocessorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "지원하지 않는 이미지 형식이에요. 다른 사진을 선택해 주세요."
        case .decodeFailed:
            return "이미지를 불러오지 못했어요. 다른 사진을 선택해 주세요."
        case .compressionFailed, .fileTooLargeAfterCompression:
            return "이미지를 업로드 가능한 크기로 변환하지 못했어요. 다른 사진을 선택해주세요."
        }
    }
}

struct ProfileImagePreprocessor {
    static let maxBytes: Int = 1 * 1024 * 1024
    static let targetBytes: Int = 900 * 1024
    private let preprocessor = ImageUploadPreprocessor(maxInitialPixel: 1_024)

    static func diagnosticMetadata(data: Data, filename: String) -> (contentType: String, pixelWidth: Int, pixelHeight: Int, orientation: String) {
        let metadata = sourceMetadata(data: data, filename: filename)
        return (
            metadata.mimeType == "unknown" ? metadata.uti : metadata.mimeType,
            Int(metadata.size.width),
            Int(metadata.size.height),
            metadata.orientation
        )
    }

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
            throw ProfileImagePreprocessorError.decodeFailed
        }

        do {
            let sourceMetadata = Self.sourceMetadata(data: data, filename: originalFileName)
            if isPNG(uti: sourceMetadata.uti),
               data.count <= Self.maxBytes {
                return ProcessedProfileImage(
                    data: data,
                    mimeType: "image/png",
                    fileExtension: "png",
                    filename: "profile.png",
                    pixelSize: sourceMetadata.size,
                    originalPixelSize: sourceMetadata.size,
                    sourceFormat: sourceMetadata.format,
                    originalUTI: sourceMetadata.uti,
                    originalMimeType: sourceMetadata.mimeType,
                    orientation: sourceMetadata.orientation,
                    byteSize: data.count,
                    originalBytes: data.count,
                    compressionQuality: 1,
                    didDownsample: false
                )
            }

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
        } catch ImageUploadPreprocessorError.unsupportedType {
            throw ProfileImagePreprocessorError.unsupportedFormat
        } catch ImageUploadPreprocessorError.cannotEncode {
            throw ProfileImagePreprocessorError.decodeFailed
        } catch ImageUploadPreprocessorError.overLimitAfterCompression {
            throw ProfileImagePreprocessorError.fileTooLargeAfterCompression
        } catch {
            throw ProfileImagePreprocessorError.compressionFailed
        }
    }

    private func isPNG(uti: String) -> Bool {
        guard let type = UTType(uti) else {
            return false
        }
        return type.conforms(to: .png)
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
