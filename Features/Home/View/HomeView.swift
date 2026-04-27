import SwiftUI

struct HomeView: View {
    private enum ScrollAnchor {
        static let top = "home-scroll-top"
    }

    private enum HomeLayout {
        static let horizontalInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 18
        static let topPadding: CGFloat = 4
        static let bottomInset: CGFloat = 8
    }

    @ObservedObject var presenter: HomePresenter

    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    let resetTrigger: Int

    var body: some View {
        Group {
            if presenter.viewState.isLoading && presenter.viewState.popularStores.isEmpty {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    LoadingView(message: "홈 화면을 준비하고 있어요")
                        .padding(PikkoSpacing.xl)
                }
            } else if shouldShowEmptyState {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    EmptyStateView(
                        title: presenter.viewState.emptyState?.title ?? "표시할 홈 정보가 없어요",
                        message: presenter.viewState.emptyState?.message ?? "잠시 후 다시 새로고침하거나 위치 권한을 확인해 주세요.",
                        actionTitle: presenter.viewState.emptyState?.actionTitle,
                        action: {
                            if presenter.viewState.emptyState?.requiresAuthentication == true {
                                onAuthTap()
                            } else {
                                Task { await presenter.send(.refreshRequested) }
                            }
                        }
                    )
                    .padding(PikkoSpacing.xl)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
                            Color.clear
                                .frame(height: 0)
                                .id(ScrollAnchor.top)

                            if let errorMessage = presenter.viewState.errorMessage {
                                ToastView(message: errorMessage, tone: .warning)
                                    .padding(.horizontal, HomeLayout.horizontalInset)
                            }

                            HomeHeaderSectionView(
                                locationLabel: presenter.viewState.locationLabel,
                                searchText: searchTextBinding,
                                popularKeywords: presenter.viewState.popularKeywords,
                                onLocationTap: {
                                    Task { await presenter.send(.locationTapped) }
                                },
                                onSearchSubmit: {
                                    Task { await presenter.send(.searchSubmitted) }
                                },
                                onPopularKeywordTap: { keyword in
                                    Task { await presenter.send(.popularKeywordTapped(keyword)) }
                                }
                            )
                            .padding(.horizontal, HomeLayout.horizontalInset)

                            HomeCategorySectionView(
                                categories: presenter.viewState.categories,
                                selectedCategoryID: presenter.viewState.selectedCategory?.id,
                                onSelect: { categoryID in
                                    Task { await presenter.send(.categoryTapped(categoryID)) }
                                }
                            )
                            .padding(.horizontal, HomeLayout.horizontalInset)

                            if !presenter.viewState.popularStores.isEmpty {
                                HomePopularStoresSectionView(
                                    stores: presenter.viewState.popularStores,
                                    imageLoader: imageLoader,
                                    onLikeTap: { storeID in
                                        Task { await presenter.send(.likeTapped(storeID)) }
                                    },
                                    onStoreTap: { storeID in
                                        Task { await presenter.send(.popularStoreTapped(storeID)) }
                                    }
                                )
                                .padding(.horizontal, HomeLayout.horizontalInset)
                            }

                            if !presenter.viewState.banners.isEmpty {
                                HomeBannerSectionView(
                                    banners: presenter.viewState.banners,
                                    imageLoader: imageLoader,
                                    onTap: { bannerID, index in
                                        Task { await presenter.send(.bannerTapped(id: bannerID, index: index)) }
                                    }
                                )
                                .padding(.horizontal, HomeLayout.horizontalInset)
                            }

                            HomePickedStoresSectionView(
                                stores: presenter.viewState.nearbyStores,
                                emptyMessage: presenter.viewState.nearbyStoresSectionMessage,
                                selectedTab: presenter.viewState.selectedNearbyStoreTab,
                                distanceSortTitle: presenter.viewState.nearbyDistanceSortTitle,
                                distanceSortSystemImage: presenter.viewState.nearbyDistanceSortSystemImage,
                                imageLoader: imageLoader,
                                onTabTap: { tab in
                                    Task { await presenter.send(.nearbyStoreTabTapped(tab)) }
                                },
                                onDistanceSortTap: {
                                    Task { await presenter.send(.nearbyDistanceSortTapped) }
                                },
                                onLikeTap: { storeID in
                                    Task { await presenter.send(.likeTapped(storeID)) }
                                },
                                onStoreTap: { storeID in
                                    Task { await presenter.send(.nearbyStoreTapped(storeID)) }
                                },
                                onStoreAppear: { storeID in
                                    Task { await presenter.send(.nearbyStoreAppeared(storeID)) }
                                }
                            )
                            .padding(.horizontal, HomeLayout.horizontalInset)
                        }
                        .padding(.top, HomeLayout.topPadding)
                    }
                    .onChange(of: resetTrigger) { _, _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(ScrollAnchor.top, anchor: .top)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: HomeLayout.bottomInset)
                }
                .background(PikkoColor.background.ignoresSafeArea())
                .refreshable {
                    await presenter.send(.refreshRequested)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { presenter.viewState.searchText },
            set: { newValue in
                Task {
                    await presenter.send(.searchTextChanged(newValue))
                }
            }
        )
    }

    private var shouldShowEmptyState: Bool {
        !presenter.viewState.isLoading
            && presenter.viewState.emptyState != nil
    }
}
