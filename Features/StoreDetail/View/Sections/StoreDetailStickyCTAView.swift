import SwiftUI

struct StoreDetailStickyCTAView: View {
    private enum Layout {
        static let buttonMinWidth: CGFloat = 128
        static let buttonHeight: CGFloat = 52
        static let quantityBadgeSize: CGFloat = 24
    }

    let summary: StoreDetailStickyCartSummary
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: PikkoSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.totalPriceText)
                    .font(PikkoTypography.title)
                    .foregroundStyle(PikkoColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                Text(summary.isEnabled ? "\(summary.itemCountText)개 담김" : "담은 메뉴 없음")
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Button(action: action) {
                HStack(spacing: PikkoSpacing.xs) {
                    Text(summary.itemCountText)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(PikkoColor.accentStrong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: Layout.quantityBadgeSize, height: Layout.quantityBadgeSize)
                        .background(.white)
                        .clipShape(Circle())

                    Text(summary.buttonTitle)
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, PikkoSpacing.md)
                .frame(minWidth: Layout.buttonMinWidth)
                .frame(height: Layout.buttonHeight)
                .background(summary.isEnabled ? PikkoColor.accent : PikkoColor.gray300)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!summary.isEnabled)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
        }
        .padding(.horizontal, PikkoSpacing.xl)
        .padding(.top, PikkoSpacing.sm)
        .padding(.bottom, PikkoSpacing.sm)
        .background(PikkoColor.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: -4)
    }
}
