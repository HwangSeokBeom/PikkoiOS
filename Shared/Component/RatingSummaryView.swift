import SwiftUI

struct RatingSummaryView: View {
    enum Size {
        case regular
        case compact
    }

    let ratingText: String
    var reviewCountText: String?
    var size: Size = .regular

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(PikkoColor.point)
            Text(ratingText)
                .font(ratingFont)
                .foregroundStyle(PikkoColor.primaryText)
            if let reviewCountText {
                Text(reviewCountText)
                    .font(reviewFont)
                    .foregroundStyle(PikkoColor.secondaryText)
            }
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .regular:
            return 12
        case .compact:
            return 10
        }
    }

    private var ratingFont: Font {
        switch size {
        case .regular:
            return PikkoTypography.bodyStrong
        case .compact:
            return PikkoTypography.captionStrong
        }
    }

    private var reviewFont: Font {
        switch size {
        case .regular:
            return PikkoTypography.body
        case .compact:
            return PikkoTypography.caption
        }
    }
}

#Preview {
    RatingSummaryView(ratingText: "4.8", reviewCountText: "(211)")
        .padding()
        .background(PikkoColor.background)
}
