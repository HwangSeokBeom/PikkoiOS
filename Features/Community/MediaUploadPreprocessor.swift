import Foundation
import UIKit
import UniformTypeIdentifiers

enum CommunityUploadConfiguration {
    static let maxAttachmentBytes = 5 * 1024 * 1024
}

struct MediaUploadPreprocessorMetadata: Equatable, Sendable {
    let originalBytes: Int
    let finalBytes: Int
    let wasResized: Bool
}

struct MediaUploadPreprocessorResult: Equatable, Sendable {
    let file: CommunityPostUploadFile
    let metadata: MediaUploadPreprocessorMetadata
}

enum MediaUploadPreprocessorError: Error, Equatable {
    case fileTooLarge
}

extension MediaUploadPreprocessorError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "파일 크기가 너무 커요. 더 작은 파일을 선택해 주세요."
        }
    }
}

struct MediaUploadPreprocessor {
    private let logger = Logger(category: "MediaUpload")

    func process(
        _ file: CommunityPostUploadFile,
        maxBytes: Int = CommunityUploadConfiguration.maxAttachmentBytes
    ) throws -> MediaUploadPreprocessorResult {
        let originalBytes = file.data.count
        guard originalBytes > maxBytes else {
            log(
                originalBytes: originalBytes,
                finalBytes: originalBytes,
                action: "skipped",
                reason: "underLimit"
            )
            return MediaUploadPreprocessorResult(
                file: file,
                metadata: MediaUploadPreprocessorMetadata(
                    originalBytes: originalBytes,
                    finalBytes: originalBytes,
                    wasResized: false
                )
            )
        }

        guard isImage(file), let image = UIImage(data: file.data) else {
            logFailure(originalBytes: originalBytes, reason: "nonImageOverLimit")
            throw MediaUploadPreprocessorError.fileTooLarge
        }

        guard let processed = compressImage(
            image,
            originalFileName: file.fileName,
            hasAlpha: image.hasAlpha,
            maxBytes: maxBytes
        ) else {
            logFailure(originalBytes: originalBytes, reason: "imageCompressionExceededLimit")
            throw MediaUploadPreprocessorError.fileTooLarge
        }

        log(
            originalBytes: originalBytes,
            finalBytes: processed.data.count,
            action: "applied",
            reason: processed.wasResized ? "resizedAndCompressed" : "compressed"
        )

        return MediaUploadPreprocessorResult(
            file: CommunityPostUploadFile(
                data: processed.data,
                fileName: processed.fileName,
                mimeType: processed.mimeType
            ),
            metadata: MediaUploadPreprocessorMetadata(
                originalBytes: originalBytes,
                finalBytes: processed.data.count,
                wasResized: processed.wasResized
            )
        )
    }

    private func isImage(_ file: CommunityPostUploadFile) -> Bool {
        if file.mimeType.lowercased().hasPrefix("image/") {
            return true
        }

        guard let type = UTType(filenameExtension: (file.fileName as NSString).pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private func compressImage(
        _ image: UIImage,
        originalFileName: String,
        hasAlpha: Bool,
        maxBytes: Int
    ) -> (data: Data, fileName: String, mimeType: String, wasResized: Bool)? {
        let dimensionScales: [CGFloat] = [1.0, 0.85, 0.7, 0.55, 0.4, 0.3, 0.2]
        let jpegQualities: [CGFloat] = [0.86, 0.76, 0.66, 0.55, 0.45, 0.35, 0.25, 0.18]

        for dimensionScale in dimensionScales {
            guard let candidate = resizedImage(image, scale: dimensionScale) else {
                continue
            }
            let wasResized = dimensionScale < 1.0

            if hasAlpha {
                if let pngData = candidate.pngData(), pngData.count <= maxBytes {
                    return (
                        data: pngData,
                        fileName: replacingExtension(of: originalFileName, with: "png"),
                        mimeType: "image/png",
                        wasResized: wasResized
                    )
                }
                continue
            }

            for quality in jpegQualities {
                guard let jpegData = candidate.jpegData(compressionQuality: quality) else {
                    continue
                }
                if jpegData.count <= maxBytes {
                    return (
                        data: jpegData,
                        fileName: replacingExtension(of: originalFileName, with: "jpg"),
                        mimeType: "image/jpeg",
                        wasResized: wasResized || quality < jpegQualities[0]
                    )
                }
            }
        }

        return nil
    }

    private func resizedImage(_ image: UIImage, scale: CGFloat) -> UIImage? {
        guard scale < 1.0 else {
            return image
        }

        let originalSize = image.size
        let targetSize = CGSize(
            width: max(1, floor(originalSize.width * scale)),
            height: max(1, floor(originalSize.height * scale))
        )
        guard targetSize.width < originalSize.width || targetSize.height < originalSize.height else {
            return image
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func replacingExtension(of fileName: String, with newExtension: String) -> String {
        let baseName = (fileName as NSString).deletingPathExtension
        return "\(baseName).\(newExtension)"
    }

    private func log(
        originalBytes: Int,
        finalBytes: Int,
        action: String,
        reason: String
    ) {
        #if DEBUG
        logger.debug(
            "[MediaUpload] originalBytes=\(originalBytes) finalBytes=\(finalBytes) action=\(action) reason=\(reason)"
        )
        #endif
    }

    private func logFailure(originalBytes: Int, reason: String) {
        #if DEBUG
        logger.warning(
            "[MediaUpload] originalBytes=\(originalBytes) finalBytes=0 action=failed reason=\(reason)"
        )
        #endif
    }
}

private extension UIImage {
    var hasAlpha: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else {
            return false
        }

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
