import Foundation
import ImageIO
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

enum UploadFieldName {
    static let profile = "profile"
    static let files = "files"
    static let menuImage = "menu_image"
}

enum ImageUploadPurpose: String, Sendable {
    case profile
    case post
    case review
    case chat
    case menu
}

struct ImageUploadPreprocessInput: Sendable {
    let data: Data
    let filename: String
    let mimeType: String
    let purpose: ImageUploadPurpose
    let targetLimitBytes: Int
}

struct ImageUploadPreprocessOutput: Equatable, Sendable {
    let data: Data
    let mimeType: String
    let filename: String
    let width: Int
    let height: Int
}

enum ImageUploadPreprocessorError: Error, Equatable {
    case unsupportedType
    case cannotEncode
    case overLimitAfterCompression
}

extension ImageUploadPreprocessorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "지원하지 않는 파일 형식입니다."
        case .cannotEncode:
            return "이미지를 처리하지 못했어요."
        case .overLimitAfterCompression:
            return "파일 용량 제한을 초과했어요. 더 작은 파일을 선택해 주세요."
        }
    }
}

struct ImageUploadPreprocessor {
    private let logger = Logger(category: "ImagePreprocess")
    private let maxInitialPixel: CGFloat

    init(maxInitialPixel: CGFloat = 2_400) {
        self.maxInitialPixel = maxInitialPixel
    }

    func process(_ input: ImageUploadPreprocessInput) throws -> ImageUploadPreprocessOutput {
        let normalizedMimeType = input.mimeType.lowercased()
        guard isProcessableImage(mimeType: normalizedMimeType, filename: input.filename) else {
            throw ImageUploadPreprocessorError.unsupportedType
        }
        guard let originalImage = downsample(data: input.data, maxPixel: maxInitialPixel) ?? UIImage(data: input.data) else {
            throw ImageUploadPreprocessorError.cannotEncode
        }

        logger.debug("[ImagePreprocess] start purpose=\(input.purpose.rawValue) originalBytes=\(input.data.count) mimeType=\(normalizedMimeType) pixel=\(Int(originalImage.size.width))x\(Int(originalImage.size.height))")

        if input.data.count <= input.targetLimitBytes,
           normalizedMimeType == "image/png" || normalizedMimeType == "image/jpeg" || normalizedMimeType == "image/jpg" {
            return ImageUploadPreprocessOutput(
                data: input.data,
                mimeType: normalizedMimeType == "image/jpg" ? "image/jpeg" : normalizedMimeType,
                filename: normalizedFilename(input.filename, mimeType: normalizedMimeType),
                width: Int(originalImage.size.width),
                height: Int(originalImage.size.height)
            )
        }

        let hasAlpha = originalImage.hasAlpha
        var pixelLimit = max(originalImage.size.width, originalImage.size.height)
        while pixelLimit >= 480 {
            let candidate = resize(originalImage, maxPixel: pixelLimit) ?? originalImage
            if hasAlpha, let pngData = candidate.pngData(), pngData.count <= input.targetLimitBytes {
                logger.debug("[ImagePreprocess] downsample result bytes=\(pngData.count) pixel=\(Int(candidate.size.width))x\(Int(candidate.size.height)) quality=png")
                logger.debug("[ImagePreprocess] success purpose=\(input.purpose.rawValue) finalBytes=\(pngData.count) underLimit=true")
                return ImageUploadPreprocessOutput(
                    data: pngData,
                    mimeType: "image/png",
                    filename: replacingExtension(of: input.filename, with: "png"),
                    width: Int(candidate.size.width),
                    height: Int(candidate.size.height)
                )
            }

            for quality in [0.88, 0.78, 0.68, 0.58, 0.48, 0.38, 0.28, 0.2] as [CGFloat] {
                guard let jpegData = candidate.jpegData(compressionQuality: quality) else { continue }
                logger.debug("[ImagePreprocess] downsample result bytes=\(jpegData.count) pixel=\(Int(candidate.size.width))x\(Int(candidate.size.height)) quality=\(String(format: "%.2f", quality))")
                if jpegData.count <= input.targetLimitBytes {
                    logger.debug("[ImagePreprocess] success purpose=\(input.purpose.rawValue) finalBytes=\(jpegData.count) underLimit=true")
                    return ImageUploadPreprocessOutput(
                        data: jpegData,
                        mimeType: "image/jpeg",
                        filename: replacingExtension(of: input.filename, with: "jpg"),
                        width: Int(candidate.size.width),
                        height: Int(candidate.size.height)
                    )
                }
            }

            pixelLimit *= 0.82
        }

        logger.warning("[ImagePreprocess] failed reason=overLimitAfterCompression")
        throw ImageUploadPreprocessorError.overLimitAfterCompression
    }

    func processIfImageOrValidate(_ input: ImageUploadPreprocessInput) throws -> ImageUploadPreprocessOutput {
        if isProcessableImage(mimeType: input.mimeType.lowercased(), filename: input.filename) {
            return try process(input)
        }
        guard input.data.count <= input.targetLimitBytes else {
            throw ImageUploadPreprocessorError.overLimitAfterCompression
        }
        throw ImageUploadPreprocessorError.unsupportedType
    }

    func isProcessableImage(mimeType: String, filename: String) -> Bool {
        let normalized = mimeType.lowercased()
        if ["image/jpeg", "image/jpg", "image/png"].contains(normalized) {
            return true
        }
        if normalized == "image/gif" || normalized == "image/webp" {
            return false
        }
        guard let type = UTType(filenameExtension: (filename as NSString).pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .jpeg) || type.conforms(to: .png)
    }

    private func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func resize(_ image: UIImage, maxPixel: CGFloat) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixel else { return image }
        let scale = maxPixel / longest
        let targetSize = CGSize(width: max(1, floor(image.size.width * scale)), height: max(1, floor(image.size.height * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func normalizedFilename(_ filename: String, mimeType: String) -> String {
        replacingExtension(of: filename, with: mimeType.contains("png") ? "png" : "jpg")
    }

    private func replacingExtension(of fileName: String, with newExtension: String) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(baseName.isEmpty ? "upload-\(Int(Date().timeIntervalSince1970))" : baseName).\(newExtension)"
    }
}

private extension UIImage {
    var hasAlpha: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .alphaOnly, .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }
}
