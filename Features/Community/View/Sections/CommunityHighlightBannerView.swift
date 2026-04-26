import SwiftUI

struct CommunityHighlightBannerView: View {
    let banner: CommunityFeaturedBanner

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: PikkoSpacing.lg) {
                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text(banner.eyebrow)
                        .font(PikkoTypography.micro)
                        .foregroundStyle(PikkoColor.sage300)

                    Text(banner.title)
                        .font(PikkoTypography.hero)
                        .foregroundStyle(PikkoColor.accentStrong)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(banner.badgeText)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PikkoSpacing.sm)
                        .frame(height: 28)
                        .background(PikkoColor.sage500)
                        .clipShape(Capsule())
                }

                Spacer(minLength: PikkoSpacing.sm)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.54))
                        .frame(width: 88, height: 88)

                    Image(systemName: banner.systemImage)
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(PikkoColor.sage500)
                        .rotationEffect(.degrees(-8))
                }
                .padding(.trailing, PikkoSpacing.sm)
            }
            .padding(.horizontal, PikkoSpacing.xl)
            .padding(.vertical, PikkoSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)

            Text(banner.pageText)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(.white)
                .padding(.horizontal, PikkoSpacing.sm)
                .frame(height: 28)
                .background(PikkoColor.ink900.opacity(0.24))
                .clipShape(Capsule())
                .padding(PikkoSpacing.md)
        }
        .background(
            LinearGradient(
                colors: [
                    PikkoColor.surfaceMuted,
                    PikkoColor.sage50
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(PikkoColor.mint200.opacity(0.38))
                .frame(width: 110, height: 110)
                .offset(x: 34, y: -44)
        }
        .clipped()
    }
}

#Preview {
    CommunityHighlightBannerView(
        banner: .init(
            eyebrow: "새싹멤버십 전용 사용 혜택",
            title: "피자부터 커피까지\n픽업하면 0원",
            badgeText: "SeSAC ONLY",
            pageText: "1 / 12",
            systemImage: "takeoutbag.and.cup.and.straw.fill"
        )
    )
}
