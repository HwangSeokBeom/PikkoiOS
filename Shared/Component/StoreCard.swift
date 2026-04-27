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
    var onCardTapped: (() -> Void)?
    var onLikeTapped: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            imageSection
            infoSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .background(.white)
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(PikkoColor.line.opacity(0.6), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private var imageSection: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if style == .list {
                    listImageLayout
                } else {
                    StoreCardImageTile(
                        path: primaryImagePath,
                        loader: loader,
                        cornerRadius: imageCornerRadius
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: imageHeight)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                onCardTapped?()
            }

            HStack(alignment: .top) {
                Button {
                    onLikeTapped?()
                } label: {
                    Image(systemName: model.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: heartIconSize, weight: .semibold))
                        .foregroundStyle(model.isLiked ? PikkoColor.coralHeart : PikkoColor.gray500)
                        .frame(width: overlayButtonSize, height: overlayButtonSize)
                        .background(.white.opacity(0.9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: PikkoSpacing.xs)

                if model.isPickupAvailable {
                    TagChip(
                        title: "픽업중",
                        systemImage: "takeoutbag.and.cup.and.straw.fill",
                        isSelected: true,
                        appearance: .filled,
                        size: .mini
                    )
                }
            }
            .padding(overlayPadding)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: infoSpacing) {
            Text(model.title)
                .font(titleFont)
                .foregroundStyle(PikkoColor.primaryText)
                .lineLimit(style == .featured ? 1 : 2)
                .multilineTextAlignment(.leading)

            HStack(spacing: metaSpacing) {
                metaBadge(systemImage: "heart.fill", text: model.likeText, tint: PikkoColor.warmYellow)
                RatingSummaryView(
                    ratingText: model.ratingText,
                    reviewCountText: model.reviewCountText,
                    size: .compact
                )
            }

            HStack(spacing: infoRowSpacing) {
                infoPill(systemImage: "location.fill", text: model.distanceText)
                infoPill(systemImage: "clock.fill", text: model.openTimeText)
                infoPill(systemImage: "figure.walk", text: model.orderCountText)
            }

            if style == .list, !model.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PikkoSpacing.xs) {
                        ForEach(model.tags, id: \.self) { tag in
                            TagChip(title: tag, appearance: .subtle, size: .mini)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onCardTapped?()
        }
    }

    private func infoPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(PikkoTypography.micro)
        }
        .foregroundStyle(PikkoColor.secondaryText)
        .lineLimit(1)
    }

    private func metaBadge(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.primaryText)
        }
    }

    @ViewBuilder
    private var listImageLayout: some View {
        switch secondaryImagePaths.count {
        case 2...:
            HStack(spacing: PikkoSpacing.xs) {
                StoreCardImageTile(
                    path: primaryImagePath,
                    loader: loader,
                    cornerRadius: imageCornerRadius
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: PikkoSpacing.xs) {
                    ForEach(Array(secondaryImagePaths.prefix(2).enumerated()), id: \.offset) { _, path in
                        StoreCardImageTile(
                            path: path,
                            loader: loader,
                            cornerRadius: secondaryImageCornerRadius
                        )
                        .frame(width: thumbnailColumnWidth, height: secondaryImageHeight)
                    }
                }
                .frame(width: thumbnailColumnWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        case 1:
            HStack(spacing: PikkoSpacing.xs) {
                StoreCardImageTile(
                    path: primaryImagePath,
                    loader: loader,
                    cornerRadius: imageCornerRadius
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StoreCardImageTile(
                    path: secondaryImagePaths.first,
                    loader: loader,
                    cornerRadius: secondaryImageCornerRadius
                )
                .frame(width: thumbnailColumnWidth, height: imageHeight)
            }
            .frame(maxHeight: .infinity)
        default:
            StoreCardImageTile(
                path: primaryImagePath,
                loader: loader,
                cornerRadius: imageCornerRadius
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var imagePathsForDisplay: [String] {
        var seen = Set<String>()

        return ([model.heroImagePath] + model.thumbnailPaths)
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private var primaryImagePath: String? {
        imagePathsForDisplay.first
    }

    private var secondaryImagePaths: [String] {
        Array(imagePathsForDisplay.dropFirst().prefix(2))
    }

    private var cardPadding: CGFloat {
        switch style {
        case .featured:
            return 10
        case .list:
            return 12
        }
    }

    private var contentSpacing: CGFloat {
        switch style {
        case .featured:
            return PikkoSpacing.sm
        case .list:
            return 10
        }
    }

    private var infoSpacing: CGFloat {
        switch style {
        case .featured:
            return 6
        case .list:
            return 8
        }
    }

    private var metaSpacing: CGFloat {
        switch style {
        case .featured:
            return PikkoSpacing.xs
        case .list:
            return PikkoSpacing.sm
        }
    }

    private var infoRowSpacing: CGFloat {
        switch style {
        case .featured:
            return 10
        case .list:
            return PikkoSpacing.sm
        }
    }

    private var imageHeight: CGFloat {
        switch style {
        case .featured:
            return 118
        case .list:
            return 132
        }
    }

    private var secondaryImageHeight: CGFloat {
        (imageHeight - PikkoSpacing.xs) / 2
    }

    private var thumbnailColumnWidth: CGFloat {
        82
    }

    private var imageCornerRadius: CGFloat {
        switch style {
        case .featured:
            return 14
        case .list:
            return 16
        }
    }

    private var secondaryImageCornerRadius: CGFloat {
        switch style {
        case .featured:
            return 14
        case .list:
            return 14
        }
    }

    private var overlayButtonSize: CGFloat {
        switch style {
        case .featured:
            return 28
        case .list:
            return 30
        }
    }

    private var heartIconSize: CGFloat {
        switch style {
        case .featured:
            return 14
        case .list:
            return 15
        }
    }

    private var overlayPadding: CGFloat {
        switch style {
        case .featured:
            return PikkoSpacing.xs
        case .list:
            return 10
        }
    }

    private var titleFont: Font {
        switch style {
        case .featured:
            return .system(size: 15, weight: .semibold)
        case .list:
            return .system(size: 16, weight: .semibold)
        }
    }

    private var cardCornerRadius: CGFloat {
        switch style {
        case .featured:
            return 18
        case .list:
            return 20
        }
    }
}

private struct StoreCardImageTile: View {
    let path: String?
    let loader: any AuthorizedImageLoading
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let path, !path.isEmpty {
                AuthorizedAsyncImage(
                    path: path,
                    loader: loader,
                    contentMode: .fill,
                    cornerRadius: cornerRadius
                )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PikkoColor.surfaceMuted)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PikkoColor.secondaryText)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
