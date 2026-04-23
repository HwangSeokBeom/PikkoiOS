import SwiftUI

struct RatingSummaryView: View {
    let ratingText: String
    var reviewCountText: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PikkoColor.point)
            Text(ratingText)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.primaryText)
            if let reviewCountText {
                Text(reviewCountText)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)
            }
        }
    }
}

#Preview {
    RatingSummaryView(ratingText: "4.8", reviewCountText: "(211)")
        .padding()
        .background(PikkoColor.background)
}
