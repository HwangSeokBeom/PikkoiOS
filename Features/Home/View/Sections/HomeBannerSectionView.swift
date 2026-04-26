import SwiftUI

struct HomeBannerSectionView: View {
    private enum Layout {
        static let height: CGFloat = 96
    }

    let banners: [HomeBannerItem]
    let imageLoader: any AuthorizedImageLoading
    let onTap: (String) -> Void

    @State private var selectedIndex = 0

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(banners.enumerated()), id: \.offset) { index, banner in
                Button {
                    onTap(banner.id)
                } label: {
                    bannerCard(for: banner)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .frame(height: Layout.height)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: banners.count) { _, newValue in
            if newValue == 0 {
                selectedIndex = 0
            } else {
                selectedIndex = min(selectedIndex, newValue - 1)
            }
        }
    }

    private func bannerCard(for banner: HomeBannerItem) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                .fill(PikkoColor.surface)

            AuthorizedAsyncImage(
                path: banner.imagePath,
                loader: imageLoader,
                contentMode: .fit,
                cornerRadius: PikkoRadius.hero,
                showsProgress: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .stroke(PikkoColor.line.opacity(0.4), lineWidth: 1)
            }

            Text("\(currentPage)/\(max(banners.count, 1))")
                .font(PikkoTypography.micro)
                .foregroundStyle(.white)
                .padding(.horizontal, PikkoSpacing.xs)
                .frame(height: 20)
                .background(PikkoColor.ink900.opacity(0.28))
                .clipShape(Capsule())
                .padding(PikkoSpacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.height)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .accessibilityLabel(banner.title)
    }

    private var currentPage: Int {
        guard !banners.isEmpty else { return 0 }
        return min(selectedIndex + 1, banners.count)
    }
}
