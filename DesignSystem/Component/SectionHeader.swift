import SwiftUI

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PikkoTypography.section)
                    .foregroundStyle(PikkoColor.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }
            }

            Spacer(minLength: PikkoSpacing.sm)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                            .font(PikkoTypography.captionStrong)
                        if let actionSystemImage {
                            Image(systemName: actionSystemImage)
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundStyle(PikkoColor.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    VStack(spacing: PikkoSpacing.xl) {
        SectionHeader(title: "실시간 인기 맛집")
        SectionHeader(title: "타임라인", actionTitle: "최신순", actionSystemImage: "line.3.horizontal.decrease", action: {})
    }
    .padding()
    .background(PikkoColor.background)
}
