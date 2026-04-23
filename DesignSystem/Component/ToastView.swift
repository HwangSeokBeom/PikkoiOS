import SwiftUI

struct ToastView: View {
    enum Tone {
        case neutral
        case success
        case warning
    }

    let message: String
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: PikkoSpacing.xs) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(PikkoTypography.captionStrong)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, PikkoSpacing.md)
        .frame(height: 42)
        .background(backgroundColor)
        .clipShape(Capsule())
        .pikkoShadow(PikkoShadow.card)
    }

    private var iconName: String {
        switch tone {
        case .neutral:
            return "sparkles"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral:
            return .white
        case .success:
            return PikkoColor.accentStrong
        case .warning:
            return PikkoColor.ink900
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return PikkoColor.accentStrong
        case .success:
            return PikkoColor.surfaceMuted
        case .warning:
            return PikkoColor.warmYellow.opacity(0.85)
        }
    }
}

#Preview {
    VStack(spacing: PikkoSpacing.md) {
        ToastView(message: "좋아요를 눌렀어요")
        ToastView(message: "업로드가 완료되었어요", tone: .success)
        ToastView(message: "네트워크 상태를 확인해주세요", tone: .warning)
    }
    .padding()
    .background(PikkoColor.background)
}
