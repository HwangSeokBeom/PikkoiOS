import SwiftUI

struct HomeBannerSectionView: View {
    let banners: [HomeBannerItem]
    let imageLoader: any AuthorizedImageLoading
    let onTap: (String) -> Void

    @State private var selectedIndex = 0

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(banners.enumerated()), id: \.element.id) { index, banner in
                Button {
                    onTap(banner.id)
                } label: {
                    bannerCard(for: banner)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, PikkoSpacing.xl)
                .tag(index)
            }
        }
        .frame(height: 146)
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func bannerCard(for banner: HomeBannerItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AuthorizedAsyncImage(
                path: banner.imagePath,
                loader: imageLoader,
                cornerRadius: PikkoRadius.hero,
                showsProgress: false
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.02),
                    Color.black.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))

            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                Text(banner.title)
                    .font(PikkoTypography.section)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: PikkoSpacing.xs) {
                    Text(banner.payloadType)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, PikkoSpacing.sm)
                        .frame(height: 24)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())

                    Spacer()

                    Text("\(selectedIndex + 1)/\(max(banners.count, 1))")
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PikkoSpacing.xs)
                        .frame(height: 24)
                        .background(PikkoColor.ink900.opacity(0.28))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, PikkoSpacing.lg)
            .padding(.vertical, PikkoSpacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 146)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
    }
}
