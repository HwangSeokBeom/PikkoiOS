import Foundation

struct ProfileImagePreprocessResult: Equatable, Sendable {
    let data: Data
    let fileName: String
    let mimeType: String
    let originalBytes: Int

    var isUnderLimit: Bool {
        data.count <= ProfileImagePreprocessor.maxBytes
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
            return "이미지 파일을 다시 선택해 주세요."
        case .exceedsLimit:
            return "프로필 이미지는 1MB 이하로 등록할 수 있어요."
        }
    }
}

struct ProfileImagePreprocessor {
    static let maxBytes = 1 * 1024 * 1024
    private let preprocessor = ImageUploadPreprocessor(maxInitialPixel: 1_600)

    func process(data: Data, originalFileName: String) throws -> ProfileImagePreprocessResult {
        guard !data.isEmpty else {
            throw ProfileImagePreprocessorError.invalidImage
        }

        do {
            let output = try preprocessor.process(
                ImageUploadPreprocessInput(
                    data: data,
                    filename: originalFileName,
                    mimeType: mimeType(from: originalFileName),
                    purpose: .profile,
                    targetLimitBytes: Self.maxBytes
                )
            )
            return ProfileImagePreprocessResult(
                data: output.data,
                fileName: output.filename,
                mimeType: output.mimeType,
                originalBytes: data.count
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
        return ext == "png" ? "image/png" : "image/jpeg"
    }
}
