import SwiftUI

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PikkoSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(PikkoTypography.bodyStrong)
            }
            .foregroundStyle(PikkoColor.primaryPressed)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(PikkoColor.primarySoft)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .stroke(PikkoColor.primary.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SecondaryButton(title: "리뷰 작성", systemImage: "star.fill", action: {})
        .padding()
        .background(PikkoColor.background)
}
