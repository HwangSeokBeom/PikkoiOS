import SwiftUI

struct SectionHeader: View {
    enum Size {
        case regular
        case compact
    }

    let title: String
    var subtitle: String?
    var actionTitle: String?
    var actionSystemImage: String?
    var action: (() -> Void)?
    var size: Size = .regular

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: subtitleSpacing) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(PikkoColor.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(subtitleFont)
                        .foregroundStyle(PikkoColor.secondaryText)
                }
            }

            Spacer(minLength: spacerLength)

            if let actionTitle {
                Group {
                    if let action {
                        Button(action: action) {
                            actionLabel(actionTitle: actionTitle)
                        }
                        .buttonStyle(.plain)
                    } else {
                        actionLabel(actionTitle: actionTitle)
                    }
                }
            }
        }
    }

    private func actionLabel(actionTitle: String) -> some View {
        HStack(spacing: 4) {
            Text(actionTitle)
                .font(actionFont)
            if let actionSystemImage {
                Image(systemName: actionSystemImage)
                    .font(.system(size: actionIconSize, weight: .semibold))
            }
        }
        .foregroundStyle(PikkoColor.secondaryText)
    }

    private var titleFont: Font {
        switch size {
        case .regular:
            return PikkoTypography.section
        case .compact:
            return .system(size: 17, weight: .bold)
        }
    }

    private var subtitleFont: Font {
        switch size {
        case .regular:
            return PikkoTypography.caption
        case .compact:
            return PikkoTypography.micro
        }
    }

    private var actionFont: Font {
        switch size {
        case .regular:
            return PikkoTypography.captionStrong
        case .compact:
            return PikkoTypography.micro
        }
    }

    private var actionIconSize: CGFloat {
        switch size {
        case .regular:
            return 11
        case .compact:
            return 10
        }
    }

    private var spacerLength: CGFloat {
        switch size {
        case .regular:
            return PikkoSpacing.sm
        case .compact:
            return PikkoSpacing.xs
        }
    }

    private var subtitleSpacing: CGFloat {
        switch size {
        case .regular:
            return 2
        case .compact:
            return 1
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
