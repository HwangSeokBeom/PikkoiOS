import SwiftUI

struct FloatingQuickActionView: View {
    @EnvironmentObject private var cartStore: CartStore
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(PikkoColor.surface)
                        .frame(width: 82, height: 82)

                    Circle()
                        .fill(PikkoColor.accent)
                        .frame(width: 68, height: 68)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }

                if cartStore.summary.itemCount > 0 {
                    Text("\(cartStore.summary.itemCount)")
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PikkoSpacing.xs)
                        .frame(height: 24)
                        .background(PikkoColor.accentStrong)
                        .clipShape(Capsule())
                        .offset(x: 6, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .pikkoShadow(PikkoShadow.floating)
        .accessibilityLabel("Open cart")
    }
}
