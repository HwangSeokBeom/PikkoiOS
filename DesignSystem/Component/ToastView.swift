import SwiftUI

struct ToastView: View {
    enum Tone {
        case neutral
        case success
        case warning
    }

    let message: String
    var tone: Tone = .neutral
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: PikkoSpacing.xs) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(PikkoTypography.captionStrong)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(PikkoTypography.captionStrong)
                        .underline()
                }
                .buttonStyle(.plain)
            }
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
            return PikkoColor.success
        case .warning:
            return PikkoColor.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral:
            return PikkoColor.primary
        case .success:
            return PikkoColor.success.opacity(0.12)
        case .warning:
            return PikkoColor.warning.opacity(0.18)
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
