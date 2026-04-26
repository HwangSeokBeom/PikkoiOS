import SwiftUI

struct CommunityView: View {
    @ObservedObject var presenter: CommunityPresenter

    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void

    var body: some View {
        Group {
            if presenter.viewState.isLoading && presenter.viewState.posts.isEmpty {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    LoadingView(message: "커뮤니티 피드를 준비하고 있어요")
                        .padding(PikkoSpacing.xl)
                }
            } else if shouldShowEmptyState {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    EmptyStateView(
                        title: presenter.viewState.emptyState?.title ?? "표시할 게시글이 없어요",
                        message: presenter.viewState.emptyState?.message ?? "검색어나 거리, 필터를 바꿔서 다시 확인해 주세요.",
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
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                                .padding(.horizontal, PikkoSpacing.xl)
                        }

                        CommunityHeaderSectionView(
                            searchText: searchTextBinding,
                            onSearchSubmit: {
                                Task { await presenter.send(.searchSubmitted) }
                            },
                            onComposeTap: {
                                Task { await presenter.send(.composeTapped) }
                            }
                        )
                        .padding(.horizontal, PikkoSpacing.xl)

                        CommunityFilterSectionView(
                            distanceOptions: presenter.viewState.distanceOptions,
                            selectedDistanceID: presenter.viewState.selectedDistance.id,
                            sortOptions: presenter.viewState.sortOptions,
                            selectedSortID: presenter.viewState.selectedSort.id,
                            filterChips: presenter.viewState.filterChips,
                            selectedFilterChipID: presenter.viewState.selectedFilterChip?.id,
                            onDistanceSelect: { distanceID in
                                Task { await presenter.send(.distanceSelected(distanceID)) }
                            },
                            onSortSelect: { sortID in
                                Task { await presenter.send(.sortSelected(sortID)) }
                            },
                            onFilterChipTap: { chipID in
                                Task { await presenter.send(.filterChipTapped(chipID)) }
                            }
                        )
                        .padding(.horizontal, PikkoSpacing.xl)

                        CommunityFeedSectionView(
                            banner: presenter.viewState.featuredBanner,
                            posts: presenter.viewState.posts,
                            selectedSortTitle: presenter.viewState.selectedSort.title,
                            imageLoader: imageLoader,
                            onPostTap: { postID in
                                Task { await presenter.send(.postTapped(postID)) }
                            },
                            onStoreSnippetTap: { storeID in
                                Task { await presenter.send(.storeSnippetTapped(storeID)) }
                            },
                            onPostAppear: { postID in
                                Task { await presenter.send(.postAppeared(postID)) }
                            },
                            onLikeTap: { postID in
                                Task { await presenter.send(.likeTapped(postID)) }
                            }
                        )
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
        !presenter.viewState.isLoading && presenter.viewState.posts.isEmpty
    }
}
