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
                        .frame(width: 74, height: 74)

                    Circle()
                        .fill(PikkoColor.accent)
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                }

                if cartStore.summary.itemCount > 0 {
                    Text("\(cartStore.summary.itemCount)")
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(PikkoColor.accentStrong)
                        .clipShape(Capsule())
                        .offset(x: 5, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .pikkoShadow(PikkoShadow.floating)
        .accessibilityLabel("Open cart")
    }
}
