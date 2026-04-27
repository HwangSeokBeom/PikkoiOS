import SwiftUI

struct HomeBannerSectionView: View {
    private enum Layout {
        static let height: CGFloat = 100
        static let autoSlideIntervalNanoseconds: UInt64 = 3_500_000_000
    }

    let banners: [HomeBannerItem]
    let imageLoader: any AuthorizedImageLoading
    let onTap: (String, Int) -> Void

    @State private var selectedIndex = 0
    @State private var autoSlideGeneration = 0
    @State private var isAutoSlideActive = false

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(banners.enumerated()), id: \.offset) { index, banner in
                Button {
                    onTap(banner.id, index)
                } label: {
                    bannerCard(for: banner)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .frame(height: Layout.height)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            startAutoSlideIfNeeded()
        }
        .onDisappear {
            stopAutoSlide()
        }
        .onChange(of: banners.count) { _, newValue in
            if newValue == 0 {
                selectedIndex = 0
            } else {
                selectedIndex = min(selectedIndex, newValue - 1)
            }

            if newValue > 1 {
                startAutoSlideIfNeeded()
            } else {
                stopAutoSlide()
            }
        }
        .onChange(of: selectedIndex) { _, _ in
            restartAutoSlideIfNeeded()
        }
        .task(id: autoSlideGeneration) {
            guard isAutoSlideActive, banners.count > 1 else { return }

            do {
                try await Task.sleep(nanoseconds: Layout.autoSlideIntervalNanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled, isAutoSlideActive, banners.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                selectedIndex = (selectedIndex + 1) % banners.count
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

    private func startAutoSlideIfNeeded() {
        guard banners.count > 1 else {
            stopAutoSlide()
            return
        }

        isAutoSlideActive = true
        autoSlideGeneration += 1
    }

    private func stopAutoSlide() {
        isAutoSlideActive = false
        autoSlideGeneration += 1
    }

    private func restartAutoSlideIfNeeded() {
        guard isAutoSlideActive else { return }

        if banners.count > 1 {
            autoSlideGeneration += 1
        } else {
            stopAutoSlide()
        }
    }
}
