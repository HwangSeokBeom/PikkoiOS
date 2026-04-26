import SwiftUI

struct StoreDetailSummarySectionView: View {
    let storeName: String
    let isPicchelin: Bool
    let isLiked: Bool
    let ratingSummary: StoreDetailRatingSummary
    let storeInfo: StoreDetailStoreInfo
    let onDirectionsTap: () -> Void
    let onChatTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
            headerSection
            if !storeInfo.descriptionText.isEmpty {
                Text(storeInfo.descriptionText)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineSpacing(4)
            }
            infoCard
            actionSummary
            PrimaryButton(title: "길찾기", action: onDirectionsTap)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            HStack(alignment: .center, spacing: PikkoSpacing.sm) {
                Text(storeName)
                    .font(PikkoTypography.title)
                    .foregroundStyle(PikkoColor.primaryText)

                if isPicchelin {
                    TagChip(
                        title: "픽슐랭",
                        systemImage: "sparkles",
                        isSelected: true,
                        appearance: .filled
                    )
                }

                Spacer()

                Button(action: onChatTap) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PikkoColor.accentStrong)
                        .frame(width: 34, height: 34)
                        .background(PikkoColor.surfaceMuted)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: PikkoSpacing.md) {
                metricLabel(systemImage: "heart.fill", text: ratingSummary.likeCountText, tint: PikkoColor.warmYellow)
                metricLabel(systemImage: "star.fill", text: "\(ratingSummary.ratingText) \(ratingSummary.reviewCountText)", tint: PikkoColor.point)
                Spacer()
                Text(ratingSummary.orderCountText)
                    .font(PikkoTypography.captionStrong)
                    .foregroundStyle(PikkoColor.tertiaryText)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            infoRow(title: "가게주소", value: storeInfo.address, systemImage: "paperplane.fill")
            infoRow(title: "영업시간", value: storeInfo.operatingHours, systemImage: "clock.fill")
            infoRow(title: "주차여부", value: storeInfo.parkingInfo, systemImage: "parkingsign.circle.fill")
        }
        .padding(PikkoSpacing.lg)
        .background(.white)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                .stroke(PikkoColor.line, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
    }

    private var actionSummary: some View {
        HStack(spacing: PikkoSpacing.sm) {
            TagChip(
                title: "\(storeInfo.expectedPickupText) (\(storeInfo.distanceText))",
                systemImage: "figure.walk",
                isSelected: true,
                appearance: .subtle
            )

            if isLiked {
                TagChip(
                    title: "찜한 가게",
                    systemImage: "heart.fill",
                    isSelected: true,
                    appearance: .subtle
                )
            }
        }
    }

    private func metricLabel(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.primaryText)
        }
    }

    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: PikkoSpacing.sm) {
            Text(title)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
                .frame(width: 62, alignment: .leading)

            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PikkoColor.sage300)

            Text(value)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.gray600)

            Spacer(minLength: 0)
        }
    }
}
