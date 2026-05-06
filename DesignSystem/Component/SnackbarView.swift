import SwiftUI

struct SnackbarView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text(title)
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.primaryText)
                    Text(message)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }

                Spacer()

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(PikkoColor.accentStrong)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(PikkoSpacing.md)
        .background(PikkoColor.surfaceElevated)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                .stroke(PikkoColor.divider.opacity(0.8), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }
}

#Preview {
    SnackbarView(
        title: "결제가 확인되지 않았어요",
        message: "잠시 후 다시 시도하거나 결제 내역을 확인해주세요.",
        actionTitle: "재시도",
        action: {}
    )
    .padding()
    .background(PikkoColor.background)
}
