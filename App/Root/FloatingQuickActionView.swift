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
                        .frame(width: 58, height: 58)

                    Circle()
                        .fill(PikkoColor.accent)
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: 19, weight: .bold))
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
                        .offset(x: 2, y: 5)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 58, height: 58)
        .contentShape(Circle())
        .pikkoShadow(PikkoShadow.floating)
        .accessibilityLabel("Open cart")
    }
}
