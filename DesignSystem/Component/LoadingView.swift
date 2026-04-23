import SwiftUI

struct LoadingView: View {
    var message = "불러오는 중이에요"

    var body: some View {
        VStack(spacing: PikkoSpacing.md) {
            ProgressView()
                .tint(PikkoColor.accent)
                .scaleEffect(1.2)
            Text(message)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .padding(PikkoSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }
}

#Preview {
    LoadingView()
        .padding()
        .background(PikkoColor.background)
}
