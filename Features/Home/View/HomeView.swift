import SwiftUI

struct HomeView: View {
    @ObservedObject var presenter: HomePresenter

    let imageLoader: any AuthorizedImageLoading

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
                        title: "표시할 홈 정보가 없어요",
                        message: "잠시 후 다시 새로고침하거나 위치 권한을 확인해 주세요.",
                        actionTitle: "다시 불러오기",
                        action: {
                            Task { await presenter.send(.refreshRequested) }
                        }
                    )
                    .padding(PikkoSpacing.xl)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                                .padding(.horizontal, PikkoSpacing.xl)
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
                            }
                        )
                        .padding(.horizontal, PikkoSpacing.xl)

                        HomeCategorySectionView(
                            categories: presenter.viewState.categories,
                            selectedCategoryID: presenter.viewState.selectedCategory?.id,
                            onSelect: { categoryID in
                                Task { await presenter.send(.categoryTapped(categoryID)) }
                            }
                        )

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
                        .padding(.horizontal, PikkoSpacing.xl)

                        HomeBannerSectionView(
                            banners: presenter.viewState.banners,
                            imageLoader: imageLoader,
                            onTap: { bannerID in
                                Task { await presenter.send(.bannerTapped(bannerID)) }
                            }
                        )

                        HomePickedStoresSectionView(
                            stores: presenter.viewState.nearbyStores,
                            imageLoader: imageLoader,
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
                        .padding(.horizontal, PikkoSpacing.xl)
                        .padding(.bottom, PikkoSpacing.xxl)
                    }
                    .padding(.top, PikkoSpacing.sm)
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
            && presenter.viewState.banners.isEmpty
            && presenter.viewState.popularStores.isEmpty
            && presenter.viewState.nearbyStores.isEmpty
    }
}
