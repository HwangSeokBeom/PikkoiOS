import SwiftUI

struct StoreCard: View {
    enum LayoutStyle {
        case featured
        case list
    }

    struct Model: Identifiable {
        let id: String
        let title: String
        let heroImagePath: String?
        let thumbnailPaths: [String]
        let pickCount: Int
        let likeText: String
        let ratingText: String
        let reviewCountText: String
        let distanceText: String
        let openTimeText: String
        let orderCountText: String
        let tags: [String]
        let isLiked: Bool
        let isPickupAvailable: Bool
    }

    let model: Model
    let loader: any AuthorizedImageLoading
    var style: LayoutStyle = .list
    var onLikeTapped: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            imageSection
            infoSection
        }
        .padding(style == .featured ? PikkoSpacing.sm : PikkoSpacing.md)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: style == .featured ? PikkoRadius.hero : PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var imageSection: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if style == .list, !model.thumbnailPaths.isEmpty {
                    HStack(spacing: PikkoSpacing.xs) {
                        AuthorizedAsyncImage(
                            path: model.heroImagePath,
                            loader: loader,
                            cornerRadius: PikkoRadius.hero
                        )

                        VStack(spacing: PikkoSpacing.xs) {
                            ForEach(model.thumbnailPaths.prefix(2), id: \.self) { path in
                                AuthorizedAsyncImage(
                                    path: path,
                                    loader: loader,
                                    cornerRadius: PikkoRadius.card
                                )
                            }
                        }
                        .frame(width: 92)
                    }
                } else {
                    AuthorizedAsyncImage(
                        path: model.heroImagePath,
                        loader: loader,
                        cornerRadius: style == .featured ? PikkoRadius.hero : PikkoRadius.card
                    )
                }
            }
            .frame(height: style == .featured ? 170 : 156)

            HStack {
                Button {
                    onLikeTapped?()
                } label: {
                    Image(systemName: model.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.isLiked ? PikkoColor.coralHeart : .white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.84))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                if model.isPickupAvailable {
                    TagChip(
                        title: "픽업됨",
                        systemImage: "takeoutbag.and.cup.and.straw.fill",
                        isSelected: true,
                        appearance: .filled
                    )
                }
            }
            .padding(PikkoSpacing.sm)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            HStack(alignment: .top) {
                Text(model.title)
                    .font(PikkoTypography.cardTitle)
                    .foregroundStyle(PikkoColor.primaryText)
                    .lineLimit(2)
                Spacer(minLength: PikkoSpacing.xs)
                if style == .featured {
                    RatingSummaryView(ratingText: model.ratingText, reviewCountText: model.reviewCountText)
                }
            }

            HStack(spacing: PikkoSpacing.sm) {
                metaBadge(systemImage: "heart.fill", text: model.likeText, tint: PikkoColor.warmYellow)
                if style == .list {
                    RatingSummaryView(ratingText: model.ratingText, reviewCountText: model.reviewCountText)
                }
            }

            HStack(spacing: PikkoSpacing.md) {
                infoPill(systemImage: "location.fill", text: model.distanceText)
                infoPill(systemImage: "clock.fill", text: model.openTimeText)
                infoPill(systemImage: "figure.walk", text: model.orderCountText)
            }

            if style == .list, !model.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PikkoSpacing.xs) {
                        ForEach(model.tags, id: \.self) { tag in
                            TagChip(title: tag, appearance: .subtle)
                        }
                    }
                }
            }
        }
    }

    private func infoPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(PikkoTypography.captionStrong)
        }
        .foregroundStyle(PikkoColor.secondaryText)
    }

    private func metaBadge(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.primaryText)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: PikkoSpacing.lg) {
            StoreCard(
                model: .init(
                    id: "featured",
                    title: "새싹 도넛 가게",
                    heroImagePath: "store-hero",
                    thumbnailPaths: [],
                    pickCount: 126,
                    likeText: "126개",
                    ratingText: "4.8",
                    reviewCountText: "(211)",
                    distanceText: "3.2km",
                    openTimeText: "7PM",
                    orderCountText: "135회",
                    tags: [],
                    isLiked: true,
                    isPickupAvailable: true
                ),
                loader: PreviewAuthorizedImageLoader(),
                style: .featured
            )

            StoreCard(
                model: .init(
                    id: "list",
                    title: "새싹 마카롱 영등포직영점",
                    heroImagePath: "store-main",
                    thumbnailPaths: ["store-side-a", "store-side-b"],
                    pickCount: 155,
                    likeText: "155개",
                    ratingText: "4.9",
                    reviewCountText: "(145)",
                    distanceText: "1.3km",
                    openTimeText: "7PM",
                    orderCountText: "288회",
                    tags: ["#통카롱", "#티라미수"],
                    isLiked: true,
                    isPickupAvailable: true
                ),
                loader: PreviewAuthorizedImageLoader(),
                style: .list
            )
        }
        .padding(PikkoSpacing.md)
    }
    .background(PikkoColor.background)
}
