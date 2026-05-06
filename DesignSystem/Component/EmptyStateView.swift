import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: PikkoSpacing.md) {
            ZStack {
                Circle()
                    .fill(PikkoColor.primarySoft)
                    .frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(PikkoColor.primary)
            }

            VStack(spacing: PikkoSpacing.xs) {
                Text(title)
                    .font(PikkoTypography.cardTitle)
                    .foregroundStyle(PikkoColor.primaryText)
                Text(message)
                    .font(PikkoTypography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PikkoColor.secondaryText)
            }

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, size: .compact, action: action)
                    .frame(maxWidth: 220)
            }
        }
        .padding(PikkoSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(PikkoColor.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }
}

#Preview {
    EmptyStateView(
        title: "아직 주문 내역이 없어요",
        message: "가까운 가게를 둘러보고 첫 픽업을 시작해보세요.",
        systemImage: "takeoutbag.and.cup.and.straw.fill",
        actionTitle: "가게 둘러보기",
        action: {}
    )
    .padding()
    .background(PikkoColor.background)
}
