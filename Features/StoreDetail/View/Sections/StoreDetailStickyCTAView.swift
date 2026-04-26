import SwiftUI

struct StoreDetailStickyCTAView: View {
    let summary: StoreDetailStickyCartSummary
    let action: () -> Void

    var body: some View {
        HStack(spacing: PikkoSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.totalPriceText)
                    .font(PikkoTypography.title)
                    .foregroundStyle(PikkoColor.primaryText)
                Text(summary.isEnabled ? "지금 담은 메뉴를 장바구니에서 확인할 수 있어요" : "원하는 메뉴를 골라 장바구니에 담아보세요")
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
            }

            Spacer(minLength: PikkoSpacing.md)

            Button(action: action) {
                HStack(spacing: PikkoSpacing.xs) {
                    Text(summary.itemCountText)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(PikkoColor.accentStrong)
                        .frame(width: 24, height: 24)
                        .background(.white)
                        .clipShape(Circle())

                    Text(summary.buttonTitle)
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, PikkoSpacing.lg)
                .frame(height: 56)
                .background(summary.isEnabled ? PikkoColor.accent : PikkoColor.gray300)
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!summary.isEnabled)
        }
        .padding(.horizontal, PikkoSpacing.xl)
        .padding(.top, PikkoSpacing.md)
        .padding(.bottom, PikkoSpacing.md)
        .background(PikkoColor.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
        .pikkoShadow(PikkoShadow.card)
    }
}
