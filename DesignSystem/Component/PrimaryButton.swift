import SwiftUI

struct PrimaryButton: View {
    enum Size {
        case regular
        case compact

        var height: CGFloat {
            switch self {
            case .regular:
                return 52
            case .compact:
                return 44
            }
        }
    }

    let title: String
    var systemImage: String?
    var isLoading = false
    var isEnabled = true
    var size: Size = .regular
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PikkoSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(title)
                    .font(PikkoTypography.bodyStrong)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .background(isEnabled ? PikkoColor.accent : PikkoColor.gray300)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .pikkoShadow(size == .regular ? PikkoShadow.card : PikkoShadowToken(color: .clear, radius: 0, x: 0, y: 0))
    }
}

#Preview {
    VStack(spacing: PikkoSpacing.md) {
        PrimaryButton(title: "길찾기", action: {})
        PrimaryButton(title: "결제하기", systemImage: "creditcard.fill", action: {})
        PrimaryButton(title: "불러오는 중", isLoading: true, action: {})
        PrimaryButton(title: "비활성", isEnabled: false, action: {})
    }
    .padding()
    .background(PikkoColor.background)
}
