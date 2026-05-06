import SwiftUI

struct VideoCardView: View {
    let model: VideoCardModel
    let imageLoader: any AuthorizedImageLoading
    let onTap: () -> Void
    let onLikeTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            thumbnail

            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                Text(model.title)
                    .font(PikkoTypography.cardTitle)
                    .foregroundStyle(PikkoColor.primaryText)
                    .lineLimit(2)

                if !model.description.isEmpty {
                    Text(model.description)
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineLimit(2)
                }

                HStack(spacing: PikkoSpacing.xs) {
                    metaPill(systemImage: "eye.fill", text: model.viewCountText)
                    metaPill(systemImage: "heart.fill", text: model.likeCountText)
                    if !model.createdAtText.isEmpty {
                        metaPill(systemImage: "calendar", text: model.createdAtText)
                    }
                }

                HStack(spacing: PikkoSpacing.xs) {
                    ForEach(model.qualityLabels, id: \.self) { quality in
                        Text(quality)
                            .font(PikkoTypography.micro)
                            .foregroundStyle(PikkoColor.primaryPressed)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(PikkoColor.primarySoft)
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: PikkoSpacing.xs)

                    Button(action: onLikeTap) {
                        Image(systemName: model.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(model.isLiked ? PikkoColor.primary : PikkoColor.secondaryText)
                            .frame(width: 36, height: 36)
                            .background(PikkoColor.surfaceElevated)
                            .clipShape(Circle())
                            .overlay {
                                Circle()
                                    .stroke(PikkoColor.divider.opacity(0.7), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLikeUpdating)
                }
            }
            .padding(.horizontal, PikkoSpacing.md)
            .padding(.bottom, PikkoSpacing.md)
        }
        .background(PikkoColor.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.divider.opacity(0.55), lineWidth: 1)
        }
        .pikkoShadow(PikkoShadow.card)
        .contentShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            AuthorizedAsyncImage(
                path: model.thumbnailURL,
                loader: imageLoader,
                contentMode: .fill,
                cornerRadius: 0
            )
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()

            HStack(spacing: PikkoSpacing.xs) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(model.durationText)
                    .font(PikkoTypography.captionStrong)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.68))
            .clipShape(Capsule())
            .padding(PikkoSpacing.sm)
        }
    }

    private func metaPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(PikkoTypography.caption)
        }
        .foregroundStyle(PikkoColor.secondaryText)
    }
}
