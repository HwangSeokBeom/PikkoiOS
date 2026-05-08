import Foundation

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
    private let imagePreprocessor = ImageUploadPreprocessor()

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

        guard imagePreprocessor.isProcessableImage(mimeType: file.mimeType, filename: file.fileName) else {
            logFailure(originalBytes: originalBytes, reason: "nonImageOverLimit")
            throw MediaUploadPreprocessorError.fileTooLarge
        }

        let processed: ImageUploadPreprocessOutput
        do {
            processed = try imagePreprocessor.process(
                ImageUploadPreprocessInput(
                    data: file.data,
                    filename: file.fileName,
                    mimeType: file.mimeType,
                    purpose: .post,
                    targetLimitBytes: maxBytes
                )
            )
        } catch {
            logFailure(originalBytes: originalBytes, reason: "imageCompressionExceededLimit")
            throw MediaUploadPreprocessorError.fileTooLarge
        }

        log(
            originalBytes: originalBytes,
            finalBytes: processed.data.count,
            action: "applied",
            reason: processed.data.count < originalBytes ? "resizedAndCompressed" : "compressed"
        )

        return MediaUploadPreprocessorResult(
            file: CommunityPostUploadFile(
                data: processed.data,
                fileName: processed.filename,
                mimeType: processed.mimeType
            ),
            metadata: MediaUploadPreprocessorMetadata(
                originalBytes: originalBytes,
                finalBytes: processed.data.count,
                wasResized: processed.data.count < originalBytes
            )
        )
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
