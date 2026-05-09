import SwiftUI
import UIKit
import ImageIO

struct AuthorizedAsyncImage: View {
    private let logger = Logger(category: "AuthorizedAsyncImage")

    private enum Phase {
        case idle
        case loading
        case success(Image)
        case failure
    }

    let path: String?
    let loader: any AuthorizedImageLoading
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = PikkoRadius.card
    var showsProgress = true
    var downsampleMaxPixelSize: CGFloat = 1_200

    @State private var phase: Phase = .idle

    var body: some View {
        ZStack {
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            case .loading:
                SkeletonView(cornerRadius: cornerRadius)
                if showsProgress {
                    ProgressView()
                        .tint(PikkoColor.accentStrong)
                }
            case .failure, .idle:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PikkoColor.surfaceMuted)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(PikkoColor.secondaryText)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: path) {
            await load()
        }
    }

    private func load() async {
        guard let path, !path.isEmpty else {
            await MainActor.run { phase = .failure }
            return
        }

        await MainActor.run { phase = .loading }

        do {
            let data = try await loader.imageData(for: path)
            guard let uiImage = await ImageDownsampler.downsample(
                data: data,
                maxPixelSize: downsampleMaxPixelSize,
                logger: logger
            ) else {
                logger.warning("Image decode failed. path=\(path)")
                await MainActor.run { phase = .failure }
                return
            }
            await MainActor.run {
                phase = .success(Image(uiImage: uiImage))
            }
#if DEBUG
            if isProfileImagePath(path) {
                Logger(category: "ProfileImage").debug("[ProfileImage] display updated url=\(path)")
            }
#endif
        } catch {
            await MainActor.run { phase = .failure }
        }
    }

    private func isProfileImagePath(_ path: String) -> Bool {
        path.contains("/profiles/") || path.contains("avatarRevision=")
    }
}

private enum ImageDownsampler {
    static func downsample(
        data: Data,
        maxPixelSize: CGFloat,
        logger: Logger
    ) async -> UIImage? {
        let start = CFAbsoluteTimeGetCurrent()
        let image = await Task.detached(priority: .utility) {
            makeDownsampledImage(data: data, maxPixelSize: maxPixelSize)
        }.value

#if DEBUG
        if let image {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
            logger.debug(
                "[ImageDecode] originalSize=\(data.count) downsampledSize=\(Int(image.size.width))x\(Int(image.size.height)) durationMs=\(durationMs)"
            )
        }
#endif
        return image
    }

    private static func makeDownsampledImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return UIImage(data: data)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize))
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    AuthorizedAsyncImage(
        path: "preview-image",
        loader: PreviewAuthorizedImageLoader(),
        cornerRadius: PikkoRadius.hero
    )
    .frame(width: 220, height: 160)
    .padding()
    .background(PikkoColor.background)
}
