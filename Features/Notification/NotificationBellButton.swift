import SwiftUI

struct NotificationBellButton: View {
    let unreadCount: Int
    let action: () -> Void

    private var badgeText: String {
        unreadCount > 99 ? "99+" : "\(unreadCount)"
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(unreadCount > 0 ? PikkoColor.accentStrong : PikkoColor.gray600)
                    .frame(width: 44, height: 44)

                if unreadCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, unreadCount > 9 ? 5 : 0)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(PikkoColor.danger)
                        .clipShape(Capsule())
                        .offset(x: 1, y: 4)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        unreadCount > 0 ? "읽지 않은 알림 \(unreadCount)개" : "알림"
    }
}

#Preview {
    HStack(spacing: PikkoSpacing.md) {
        NotificationBellButton(unreadCount: 0) {}
        NotificationBellButton(unreadCount: 4) {}
        NotificationBellButton(unreadCount: 120) {}
    }
    .padding()
    .background(PikkoColor.background)
}
