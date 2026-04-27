import SwiftUI

struct CommunityView: View {
    @ObservedObject var presenter: CommunityPresenter

    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                if let errorMessage = presenter.viewState.errorMessage,
                   !shouldShowEmptyState {
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
                    selectedFilterChipIDs: presenter.viewState.selectedFilterChipIDs,
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

                feedContent
            }
            .padding(.top, PikkoSpacing.sm)
        }
        .background(PikkoColor.background.ignoresSafeArea())
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if presenter.viewState.isLoading && presenter.viewState.posts.isEmpty {
            LoadingView(message: "커뮤니티 피드를 준비하고 있어요")
                .frame(maxWidth: .infinity)
                .padding(PikkoSpacing.xl)
                .padding(.top, PikkoSpacing.xl)
        } else if shouldShowEmptyState {
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
            .frame(maxWidth: .infinity)
            .padding(PikkoSpacing.xl)
            .padding(.top, PikkoSpacing.xl)
        } else {
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
            .padding(.bottom, PikkoSpacing.xxl + RootTabBarMetrics.scrollContentBottomInset)
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
        guard !presenter.viewState.isLoading else {
            return false
        }

        switch presenter.viewState.feedStatus {
        case .empty, .failure, .locationRequired, .authenticationRequired:
            return true
        case .loading, .content:
            return false
        }
    }
}
