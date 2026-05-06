import SwiftUI

struct CommunityCard: View {
    struct Media: Identifiable, Equatable {
        let id: String
        let path: String?
    }

    struct StoreSnippet: Equatable {
        let id: String
        let title: String
        let subtitle: String
        let imagePath: String?
    }

    struct Model: Identifiable, Equatable {
        let id: String
        let authorID: String
        let authorName: String
        let authorAvatarPath: String?
        let canChatWithAuthor: Bool
        let timeText: String
        let title: String
        let bodyText: String
        let likeText: String
        let distanceText: String
        let media: [Media]
        let storeSnippet: StoreSnippet?
        let isLiked: Bool
    }

    let model: Model
    let loader: any AuthorizedImageLoading
    var onCardTapped: (() -> Void)?
    var onAuthorChatTapped: ((String) -> Void)?
    var onLikeTapped: (() -> Void)?
    var onStoreSnippetTapped: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            authorHeader
            if !model.media.isEmpty {
                mediaMosaic
            }
            contentSection
            if let storeSnippet = model.storeSnippet {
                snippetView(storeSnippet)
            }
        }
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.elevatedSurface)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.divider.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
        .contentShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .onTapGesture {
            onCardTapped?()
        }
    }

    private var authorHeader: some View {
        HStack(spacing: PikkoSpacing.sm) {
            AuthorizedAsyncImage(
                path: model.authorAvatarPath,
                loader: loader,
                contentMode: .fill,
                cornerRadius: PikkoRadius.pill,
                showsProgress: false
            )
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.authorName)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
                Text(model.timeText)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
            }

            Spacer(minLength: PikkoSpacing.sm)

            if model.canChatWithAuthor {
                Button {
                    onAuthorChatTapped?(model.authorID)
                } label: {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PikkoColor.primary)
                        .frame(width: 32, height: 32)
                        .background(PikkoColor.primarySoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var mediaMosaic: some View {
        ZStack(alignment: .topLeading) {
            if model.media.count == 1 {
                mediaTile(model.media[0], showsPlayOverlay: true)
                    .frame(maxWidth: .infinity, minHeight: 168, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: PikkoSpacing.xs) {
                        mediaTile(model.media[safe: 0], showsPlayOverlay: true)
                            .frame(width: primaryWidth(totalWidth: geometry.size.width))

                        if model.media.count == 2 {
                            mediaTile(model.media[safe: 1], showsPlayOverlay: false)
                                .frame(width: secondaryWidth(totalWidth: geometry.size.width))
                        } else {
                            VStack(spacing: PikkoSpacing.xs) {
                                mediaTile(model.media[safe: 1], showsPlayOverlay: false)
                                mediaTile(
                                    model.media[safe: 2],
                                    showsPlayOverlay: false,
                                    trailingCount: max(model.media.count - 3, 0)
                                )
                            }
                            .frame(width: secondaryWidth(totalWidth: geometry.size.width))
                        }
                    }
                }
            }

            Button {
                onLikeTapped?()
            } label: {
                Image(systemName: model.isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(PikkoSpacing.xs)
        }
        .frame(height: mediaHeight)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            Text(model.title)
                .font(PikkoTypography.cardTitle)
                .foregroundStyle(PikkoColor.primaryText)
                .lineLimit(2)

            HStack(spacing: PikkoSpacing.md) {
                Button {
                    onLikeTapped?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(model.isLiked ? PikkoColor.primary : PikkoColor.textTertiary)
                        Text(model.likeText)
                    }
                    .frame(minWidth: 56, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(PikkoColor.primary)
                    Text(model.distanceText)
                }
            }
            .font(PikkoTypography.bodyStrong)
            .foregroundStyle(PikkoColor.primaryText)

            Text(model.bodyText)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
                .lineSpacing(4)
                .lineLimit(4)
        }
    }

    private func snippetView(_ snippet: StoreSnippet) -> some View {
        Button {
            onStoreSnippetTapped?(snippet.id)
        } label: {
            HStack(spacing: PikkoSpacing.sm) {
                AuthorizedAsyncImage(
                    path: snippet.imagePath,
                    loader: loader,
                    contentMode: .fill,
                    cornerRadius: PikkoRadius.card
                )
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(snippet.title)
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.primaryPressed)
                    Text(snippet.subtitle)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }
                Spacer()
            }
            .padding(PikkoSpacing.xs)
            .background(PikkoColor.primarySoft)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(PikkoColor.primary.opacity(0.16), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func mediaTile(
        _ media: Media?,
        showsPlayOverlay: Bool,
        trailingCount: Int = 0
    ) -> some View {
        ZStack(alignment: .topLeading) {
            AuthorizedAsyncImage(
                path: media?.path,
                loader: loader,
                contentMode: .fill,
                cornerRadius: PikkoRadius.card
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if showsPlayOverlay, media != nil, MediaTypeResolver.resolve(from: media?.path ?? "") == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.92))
            }

            if trailingCount > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("+\(trailingCount)")
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, PikkoSpacing.xs)
                            .frame(height: 24)
                            .background(.black.opacity(0.34))
                            .clipShape(Capsule())
                            .padding(PikkoSpacing.xs)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private var mediaHeight: CGFloat {
        model.media.count == 1 ? 190 : 210
    }

    private func primaryWidth(totalWidth: CGFloat) -> CGFloat {
        totalWidth * 0.62
    }

    private func secondaryWidth(totalWidth: CGFloat) -> CGFloat {
        totalWidth * 0.38 - PikkoSpacing.xs
    }
}

#Preview {
    ScrollView {
        CommunityCard(
            model: .init(
                id: "community-1",
                authorID: "author-1",
                authorName: "새싹 초록록 찹찹",
                authorAvatarPath: "avatar-green",
                canChatWithAuthor: true,
                timeText: "51분 전",
                title: "입안에서 피어나는 봄, 도넛 한 입",
                bodyText: "가게 문을 열자마자 퍼지는 달콤한 향기, 작은 도넛 위에 얹힌 새싹처럼 싱그러운 상상력. 한 입 베어물면 부드럽게 퍼지는 포근한 맛에 잠시 멈춰 서서 봄날을 음미하게 돼요.",
                likeText: "12개",
                distanceText: "102m",
                media: [
                    .init(id: "media-1", path: "media-video.mov"),
                    .init(id: "media-2", path: "media-photo-a"),
                    .init(id: "media-3", path: "media-photo-b")
                ],
                storeSnippet: .init(
                    id: "store-1",
                    title: "새싹 도넛 가게",
                    subtitle: "디저트 · 서울 영등포구 선유로9길 30",
                    imagePath: "store-snippet"
                ),
                isLiked: false
            ),
            loader: PreviewAuthorizedImageLoader()
        )
    }
    .background(PikkoColor.background)
}
