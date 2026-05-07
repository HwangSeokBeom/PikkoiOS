import Foundation
import UIKit
import UniformTypeIdentifiers

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

    func process(data: Data, originalFileName: String) throws -> ProfileImagePreprocessResult {
        guard !data.isEmpty,
              let image = UIImage(data: data) else {
            throw ProfileImagePreprocessorError.invalidImage
        }

        let originalBytes = data.count
        let preferredExtension = normalizedImageExtension(from: originalFileName)
        if originalBytes <= Self.maxBytes,
           let preferredExtension,
           isSupportedImageExtension(preferredExtension) {
            let mimeType = preferredExtension == "png" ? "image/png" : "image/jpeg"
            return ProfileImagePreprocessResult(
                data: data,
                fileName: replacingExtension(of: originalFileName, with: preferredExtension == "jpeg" ? "jpg" : preferredExtension),
                mimeType: mimeType,
                originalBytes: originalBytes
            )
        }

        guard let compressed = compress(image: image, originalFileName: originalFileName) else {
            throw ProfileImagePreprocessorError.exceedsLimit
        }

        return ProfileImagePreprocessResult(
            data: compressed.data,
            fileName: compressed.fileName,
            mimeType: compressed.mimeType,
            originalBytes: originalBytes
        )
    }

    private func compress(image: UIImage, originalFileName: String) -> (data: Data, fileName: String, mimeType: String)? {
        let dimensionScales: [CGFloat] = [1.0, 0.85, 0.7, 0.55, 0.4, 0.3, 0.2]
        let qualities: [CGFloat] = [0.9, 0.82, 0.74, 0.66, 0.58, 0.5, 0.42, 0.34, 0.26, 0.18]

        for scale in dimensionScales {
            guard let candidate = resizedImage(image, scale: scale) else {
                continue
            }

            for quality in qualities {
                guard let jpegData = candidate.jpegData(compressionQuality: quality),
                      jpegData.count <= Self.maxBytes else {
                    continue
                }

                return (
                    data: jpegData,
                    fileName: replacingExtension(of: originalFileName, with: "jpg"),
                    mimeType: "image/jpeg"
                )
            }
        }

        return nil
    }

    private func resizedImage(_ image: UIImage, scale: CGFloat) -> UIImage? {
        guard scale < 1.0 else {
            return image
        }

        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func normalizedImageExtension(from fileName: String) -> String? {
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        if !fileExtension.isEmpty {
            return fileExtension
        }

        guard let type = UTType(filenameExtension: fileExtension),
              type.conforms(to: .image) else {
            return nil
        }
        return type.preferredFilenameExtension?.lowercased()
    }

    private func isSupportedImageExtension(_ fileExtension: String) -> Bool {
        ["jpg", "jpeg", "png"].contains(fileExtension)
    }

    private func replacingExtension(of fileName: String, with newExtension: String) -> String {
        let fallbackBaseName = "profile-\(Int(Date().timeIntervalSince1970))"
        let baseName = (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? fallbackBaseName : (fileName as NSString).deletingPathExtension
        return "\(baseName).\(newExtension)"
    }
}
