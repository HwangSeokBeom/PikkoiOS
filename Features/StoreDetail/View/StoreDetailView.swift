import SwiftUI

struct StoreDetailView: View {
    private enum Layout {
        static let heroHeight: CGFloat = 300
        static let navigationHeight: CGFloat = 56
        static let navigationFadeStart: CGFloat = 168
        static let navigationFadeDistance: CGFloat = 72
        static let reviewEligibilityBannerID = "reviewEligibilityBanner"
        static let contentBottomPadding: CGFloat = 24
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var presenter: StoreDetailPresenter

    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    @State private var navigationOverlayAlpha: CGFloat = 0
    @State private var reviewEligibilityBannerFrame: CGRect = .null

    var body: some View {
        ZStack(alignment: .top) {
            PikkoColor.background
                .ignoresSafeArea()

            if presenter.viewState.isLoading && !presenter.viewState.hasLoadedContent {
                LoadingView(message: "가게 상세를 준비하고 있어요")
                    .padding(PikkoSpacing.xl)
            } else if let emptyState = presenter.viewState.emptyState,
                      !presenter.viewState.hasLoadedContent {
                EmptyStateView(
                    title: emptyState.title,
                    message: emptyState.message,
                    actionTitle: emptyState.actionTitle,
                    action: {
                        if emptyState.requiresAuthentication {
                            onAuthTap()
                        } else {
                            Task { await presenter.send(.retryTapped) }
                        }
                    }
                )
                .padding(PikkoSpacing.xl)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: StoreDetailScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("storeDetailScroll")).minY
                            )
                        }
                        .frame(height: 0)

                        VStack(spacing: 0) {
                            StoreDetailHeroSectionView(
                                imagePaths: presenter.viewState.heroImages,
                                isLiked: presenter.viewState.isLiked,
                                imageLoader: imageLoader,
                                onBackTap: { dismiss() },
                                onLikeTap: {
                                    Task { await presenter.send(.likeTapped) }
                                }
                            )

                            VStack(alignment: .leading, spacing: PikkoSpacing.xxl) {
                                if let errorMessage = presenter.viewState.errorMessage {
                                    ToastView(message: errorMessage, tone: .warning)
                                }

                                if let successMessage = presenter.viewState.successMessage {
                                    ToastView(message: successMessage, tone: .success)
                                }

                                if let reviewEligibilityMessage = presenter.viewState.reviewEligibilityMessage {
                                    reviewEligibilityBanner(message: reviewEligibilityMessage)
                                        .id(Layout.reviewEligibilityBannerID)
                                        .background(
                                            GeometryReader { proxy in
                                                Color.clear.preference(
                                                    key: StoreDetailReviewEligibilityBannerFramePreferenceKey.self,
                                                    value: proxy.frame(in: .named("storeDetailScroll"))
                                                )
                                            }
                                        )
                                }

                                StoreDetailSummarySectionView(
                                    storeName: presenter.viewState.storeName,
                                    isPicchelin: presenter.viewState.isPicchelin,
                                    isLiked: presenter.viewState.isLiked,
                                    ratingSummary: presenter.viewState.ratingSummary,
                                    storeInfo: presenter.viewState.storeInfo,
                                    onDirectionsTap: {
                                        Task { await presenter.send(.directionsTapped) }
                                    },
                                    onChatTap: {
                                        Task { await presenter.send(.chatTapped) }
                                    }
                                )

                                StoreDetailMenuSectionView(
                                    menuFilters: presenter.viewState.menuFilters,
                                    selectedFilterID: presenter.viewState.selectedMenuFilter.id,
                                    sections: presenter.viewState.menuSections,
                                    imageLoader: imageLoader,
                                    onFilterTap: { filterID in
                                        Task { await presenter.send(.menuFilterTapped(filterID)) }
                                    },
                                    onIncrementTap: { menuID in
                                        Task { await presenter.send(.menuIncrementTapped(menuID)) }
                                    },
                                    onDecrementTap: { menuID in
                                        Task { await presenter.send(.menuDecrementTapped(menuID)) }
                                    }
                                )

                                StoreDetailReviewSummarySectionView(
                                    ratingSummary: presenter.viewState.ratingSummary,
                                    reviewPreview: presenter.viewState.reviewPreview,
                                    ratingBars: presenter.viewState.reviewRatings,
                                    onWriteTapped: {
                                        Task { await presenter.send(.reviewWriteTapped) }
                                    },
                                    onEditTapped: {
                                        Task { await presenter.send(.reviewEditTapped) }
                                    },
                                    onDeleteTapped: {
                                        Task { await presenter.send(.reviewDeleteTapped) }
                                    }
                                )
                            }
                            .padding(.horizontal, PikkoSpacing.xl)
                            .padding(.top, PikkoSpacing.xl)
                            .padding(.bottom, Layout.contentBottomPadding)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 30,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 30,
                                    style: .continuous
                                )
                                .fill(PikkoColor.background)
                            )
                            .offset(y: -24)
                            .padding(.bottom, -24)
                        }
                    }
                    .coordinateSpace(name: "storeDetailScroll")
                    .onPreferenceChange(StoreDetailScrollOffsetPreferenceKey.self) { minY in
                        navigationOverlayAlpha = navigationAlpha(for: -minY)
                    }
                    .onPreferenceChange(StoreDetailReviewEligibilityBannerFramePreferenceKey.self) { frame in
                        reviewEligibilityBannerFrame = frame
                    }
                    .onChange(of: presenter.viewState.reviewEligibilityScrollTrigger) { _, _ in
                        scrollToReviewEligibilityBanner(using: scrollProxy)
                    }
                }
            }

            storeDetailNavigationOverlay
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.viewState.stickyCartSummary.isEnabled {
                StoreDetailStickyCTAView(
                    summary: presenter.viewState.stickyCartSummary,
                    action: {
                        Task { await presenter.send(.stickyCTATapped) }
                    }
                )
                .padding(.bottom, RootTabBarMetrics.contentHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: presenter.viewState.stickyCartSummary.isEnabled)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func reviewEligibilityBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: PikkoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PikkoColor.ink900)
                .padding(.top, 1)

            Text(message)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.ink900)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PikkoSpacing.md)
        .padding(.vertical, PikkoSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PikkoColor.warmYellow.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var storeDetailNavigationOverlay: some View {
        HStack(spacing: PikkoSpacing.md) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PikkoColor.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.88))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(navigationOverlayAlpha)

            Text(presenter.viewState.storeName.isEmpty ? "가게 상세" : presenter.viewState.storeName)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.primaryText)
                .lineLimit(1)
                .opacity(navigationOverlayAlpha)

            Spacer(minLength: PikkoSpacing.sm)
        }
        .padding(.horizontal, PikkoSpacing.lg)
        .frame(height: Layout.navigationHeight)
        .background(
            Color.white
                .opacity(0.92 * navigationOverlayAlpha)
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PikkoColor.line.opacity(0.8 * navigationOverlayAlpha))
                .frame(height: 1)
        }
        .shadow(
            color: Color.black.opacity(0.08 * navigationOverlayAlpha),
            radius: 12,
            x: 0,
            y: 4
        )
        .allowsHitTesting(navigationOverlayAlpha > 0.08)
        .animation(.easeInOut(duration: 0.16), value: navigationOverlayAlpha)
    }

    private func navigationAlpha(for offset: CGFloat) -> CGFloat {
        let progress = (offset - Layout.navigationFadeStart) / Layout.navigationFadeDistance
        return min(max(progress, 0), 1)
    }

    private func scrollToReviewEligibilityBanner(using scrollProxy: ScrollViewProxy) {
        guard presenter.viewState.reviewEligibilityMessage != nil else { return }

        let visibleTop = Layout.navigationHeight + PikkoSpacing.sm
        let visibleBottom = UIScreen.main.bounds.height - PikkoSpacing.xxl
        let isBannerVisible = reviewEligibilityBannerFrame != .null
            && reviewEligibilityBannerFrame.minY >= visibleTop
            && reviewEligibilityBannerFrame.maxY <= visibleBottom

        guard !isBannerVisible else { return }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.28)) {
                scrollProxy.scrollTo(Layout.reviewEligibilityBannerID, anchor: .top)
            }
        }
    }
}

private struct StoreDetailScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct StoreDetailReviewEligibilityBannerFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
