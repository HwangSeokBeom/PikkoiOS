import SwiftUI

struct SkeletonView: View {
    var cornerRadius: CGFloat = PikkoRadius.card

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(PikkoColor.skeletonBase)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [
                            PikkoColor.skeletonBase.opacity(0.1),
                            PikkoColor.skeletonHighlight,
                            PikkoColor.skeletonBase.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * proxy.size.width * 1.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

#Preview {
    VStack(spacing: PikkoSpacing.md) {
        SkeletonView(cornerRadius: PikkoRadius.hero)
            .frame(height: 180)
        HStack {
            SkeletonView()
                .frame(width: 120, height: 14)
            Spacer()
        }
        HStack {
            SkeletonView()
                .frame(width: 200, height: 14)
            Spacer()
        }
    }
    .padding()
    .background(PikkoColor.background)
}
