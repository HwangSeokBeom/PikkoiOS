import SwiftUI
import UIKit

struct AuthorizedAsyncImage: View {
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

    @MainActor
    private func load() async {
        guard let path, !path.isEmpty else {
            phase = .failure
            return
        }

        phase = .loading

        do {
            let data = try await loader.imageData(for: path)
            guard let uiImage = UIImage(data: data) else {
                phase = .failure
                return
            }
            phase = .success(Image(uiImage: uiImage))
        } catch {
            phase = .failure
        }
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
