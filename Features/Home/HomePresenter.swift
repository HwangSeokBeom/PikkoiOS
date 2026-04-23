import Foundation

@MainActor
final class HomePresenter: ObservableObject {
    @Published private(set) var viewState: HomeViewState

    private let interactor: HomeInteracting
    private let router: HomeRouting
    private let distanceFormatter = DistanceFormatter()

    private var hasLoaded = false
    private var isPaging = false

    init(interactor: HomeInteracting, router: HomeRouting) {
        self.interactor = interactor
        self.router = router

        var initialState = HomeViewState()
        initialState.selectedCategory = HomeCategoryItem.all.first(where: { $0.id == "dessert" })
        self.viewState = initialState
    }

    func send(_ action: HomeAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await loadHome(isRefresh: false)
        case .refreshRequested:
            await loadHome(isRefresh: true)
        case .locationTapped:
            router.routeToLocationPicker()
        case .searchTextChanged(let text):
            viewState.searchText = text
        case .searchSubmitted:
            router.routeToSearch(query: viewState.searchText)
        case .categoryTapped(let categoryID):
            viewState.selectedCategory = viewState.categories.first(where: { $0.id == categoryID })
            await loadHome(isRefresh: false)
        case .bannerTapped(let bannerID):
            router.routeToBanner(id: bannerID)
        case .popularStoreTapped(let storeID), .nearbyStoreTapped(let storeID):
            router.routeToStoreDetail(storeID: storeID)
        case .nearbyStoreAppeared(let storeID):
            await loadNextPageIfNeeded(triggeredBy: storeID)
        case .likeTapped(let storeID):
            await toggleLike(for: storeID)
        }
    }

    private func loadHome(isRefresh: Bool) async {
        if isRefresh || hasLoaded {
            viewState.isRefreshing = true
        } else {
            viewState.isLoading = true
        }
        viewState.errorMessage = nil

        do {
            let content = try await interactor.loadHome(category: selectedCategoryAPIValue)
            apply(content: content)
            hasLoaded = true
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
        }

        viewState.isLoading = false
        viewState.isRefreshing = false
    }

    private func loadNextPageIfNeeded(triggeredBy storeID: String) async {
        guard !isPaging,
              let nextCursor = viewState.nextCursor,
              storeID == viewState.nearbyStores.last?.id else {
            return
        }

        isPaging = true
        defer { isPaging = false }

        do {
            let nextPage = try await interactor.loadMoreNearbyStores(
                category: selectedCategoryAPIValue,
                nextCursor: nextCursor
            )
            viewState.nearbyStores.append(contentsOf: nextPage.items.map(makeStoreCardModel))
            viewState.nextCursor = nextPage.nextCursor
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func toggleLike(for storeID: String) async {
        let previousPopularStores = viewState.popularStores
        let previousNearbyStores = viewState.nearbyStores

        guard let previousStore = previousPopularStores.first(where: { $0.id == storeID })
            ?? previousNearbyStores.first(where: { $0.id == storeID }) else {
            return
        }

        let optimisticLikeStatus = !previousStore.isLiked
        applyLikeStatus(optimisticLikeStatus, to: storeID)

        do {
            let confirmedLikeStatus = try await interactor.updateLikeStatus(
                storeID: storeID,
                isLiked: optimisticLikeStatus
            )
            applyLikeStatus(confirmedLikeStatus, to: storeID)
        } catch {
            viewState.popularStores = previousPopularStores
            viewState.nearbyStores = previousNearbyStores
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func apply(content: HomeContent) {
        viewState.locationLabel = content.locationLabel
        viewState.popularKeywords = content.popularKeywords
        viewState.banners = content.banners.map(makeBannerItem)
        viewState.popularStores = content.popularStores.map(makeStoreCardModel)
        viewState.nearbyStores = content.nearbyStoresPage.items.map(makeStoreCardModel)
        viewState.nextCursor = content.nearbyStoresPage.nextCursor
    }

    private func applyLikeStatus(_ isLiked: Bool, to storeID: String) {
        viewState.popularStores = viewState.popularStores.map { updatedLikeModel($0, storeID: storeID, isLiked: isLiked) }
        viewState.nearbyStores = viewState.nearbyStores.map { updatedLikeModel($0, storeID: storeID, isLiked: isLiked) }
    }

    private func updatedLikeModel(_ model: StoreCard.Model, storeID: String, isLiked: Bool) -> StoreCard.Model {
        guard model.id == storeID else {
            return model
        }

        let delta: Int
        switch (model.isLiked, isLiked) {
        case (true, false):
            delta = -1
        case (false, true):
            delta = 1
        default:
            delta = 0
        }

        let updatedCount = max(model.pickCount + delta, 0)

        return .init(
            id: model.id,
            title: model.title,
            heroImagePath: model.heroImagePath,
            thumbnailPaths: model.thumbnailPaths,
            pickCount: updatedCount,
            likeText: "\(updatedCount)개",
            ratingText: model.ratingText,
            reviewCountText: model.reviewCountText,
            distanceText: model.distanceText,
            openTimeText: model.openTimeText,
            orderCountText: model.orderCountText,
            tags: model.tags,
            isLiked: isLiked,
            isPickupAvailable: model.isPickupAvailable
        )
    }

    private var selectedCategoryAPIValue: String? {
        viewState.selectedCategory?.apiValue
    }

    private func makeBannerItem(_ banner: Banner) -> HomeBannerItem {
        HomeBannerItem(
            id: banner.id,
            title: banner.name,
            imagePath: banner.imagePath,
            payloadType: banner.payloadType,
            payloadValue: banner.payloadValue
        )
    }

    private func makeStoreCardModel(_ store: StoreSummary) -> StoreCard.Model {
        let tags = normalizedTags(from: store)

        return .init(
            id: store.id,
            title: store.name,
            heroImagePath: store.imagePaths.first,
            thumbnailPaths: Array(store.imagePaths.dropFirst().prefix(2)),
            pickCount: store.likeCount,
            likeText: "\(store.likeCount)개",
            ratingText: formattedRating(from: store.totalRating),
            reviewCountText: "(\(store.totalReviewCount))",
            distanceText: formattedDistance(from: store.distanceMeters),
            openTimeText: store.closeTime ?? "-",
            orderCountText: "\(store.totalOrderCount)회",
            tags: tags,
            isLiked: store.isLiked,
            isPickupAvailable: false
        )
    }

    private func normalizedTags(from store: StoreSummary) -> [String] {
        if !store.hashTags.isEmpty {
            return store.hashTags
        }

        if store.isPicchelin {
            return ["#픽슐랭"]
        }

        return []
    }

    private func formattedRating(from rating: Double?) -> String {
        guard let rating else { return "-" }
        return String(format: "%.1f", rating)
    }

    private func formattedDistance(from distance: Double?) -> String {
        guard let distance else { return "-" }
        return distanceFormatter.string(fromMeters: distance)
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}
