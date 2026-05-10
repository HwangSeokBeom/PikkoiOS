import SwiftUI
import UIKit
import ImageIO

struct AuthorizedAsyncImage: View {
    private let logger = Logger(category: "AuthorizedAsyncImage")

    private enum Phase {
        case idle
        case loading
        case success(Image)
        case animatedGIF(Data)
        case failure
    }

    let path: String?
    let loader: any AuthorizedImageLoading
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = PikkoRadius.card
    var showsProgress = true
    var downsampleMaxPixelSize: CGFloat = 1_200
    var onImageSizeResolved: ((CGSize) -> Void)? = nil

    @State private var phase: Phase = .idle

    var body: some View {
        ZStack {
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            case .animatedGIF(let data):
                AnimatedGIFImage(data: data, contentMode: contentMode)
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
            if ImageFormatDetector.isGIF(data: data, path: path) {
                let imageSize = ImageMetadata.pixelSize(from: data)
                await MainActor.run {
                    phase = .animatedGIF(data)
                    if let imageSize {
                        onImageSizeResolved?(imageSize)
                    }
                }
#if DEBUG
                logger.debug("[ImageDecode] animatedGIF originalSize=\(data.count) path=\(path)")
#endif
                return
            }
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
                onImageSizeResolved?(uiImage.size)
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

private struct AnimatedGIFImage: UIViewRepresentable {
    let data: Data
    let contentMode: ContentMode

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        imageView.contentMode = uiViewContentMode
        imageView.image = AnimatedGIFDecoder.animatedImage(data: data) ?? UIImage(data: data)
        imageView.startAnimating()
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.contentMode = uiViewContentMode
        uiView.image = AnimatedGIFDecoder.animatedImage(data: data) ?? UIImage(data: data)
        uiView.startAnimating()
    }

    private var uiViewContentMode: UIView.ContentMode {
        switch contentMode {
        case .fit:
            return .scaleAspectFit
        case .fill:
            return .scaleAspectFill
        @unknown default:
            return .scaleAspectFill
        }
    }
}

private enum ImageFormatDetector {
    static func isGIF(data: Data, path: String?) -> Bool {
        if path?.lowercased().hasSuffix(".gif") == true {
            return true
        }
        guard data.count >= 6,
              let header = String(bytes: data.prefix(6), encoding: .ascii) else {
            return false
        }
        return header == "GIF87a" || header == "GIF89a"
    }
}

private enum AnimatedGIFDecoder {
    static func animatedImage(data: Data) -> UIImage? {
        let options = [kCGImageSourceShouldCache: true] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            return UIImage(data: data)
        }

        var images: [UIImage] = []
        images.reserveCapacity(frameCount)
        var duration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            duration += frameDuration(at: index, source: source)
            images.append(UIImage(cgImage: cgImage))
        }

        guard !images.isEmpty else {
            return UIImage(data: data)
        }
        return UIImage.animatedImage(with: images, duration: max(duration, 0.1))
    }

    private static func frameDuration(at index: Int, source: CGImageSource) -> TimeInterval {
        let defaultDelay = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return defaultDelay
        }
        let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber
        let clamped = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber
        let delay = unclamped?.doubleValue ?? clamped?.doubleValue ?? defaultDelay
        return delay < 0.02 ? defaultDelay : delay
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

private enum ImageMetadata {
    static func pixelSize(from data: Data) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              pixelWidth.doubleValue > 0,
              pixelHeight.doubleValue > 0 else {
            return nil
        }
        return CGSize(width: pixelWidth.doubleValue, height: pixelHeight.doubleValue)
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
