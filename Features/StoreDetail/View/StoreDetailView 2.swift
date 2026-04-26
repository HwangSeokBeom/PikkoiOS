import SwiftUI

struct StoreDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var presenter: StoreDetailPresenter

    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void

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
                ScrollView(showsIndicators: false) {
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
                        .padding(.bottom, PikkoSpacing.xxl + 44)
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
                .ignoresSafeArea(edges: .top)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StoreDetailStickyCTAView(
                summary: presenter.viewState.stickyCartSummary,
                action: {
                    Task { await presenter.send(.stickyCTATapped) }
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
