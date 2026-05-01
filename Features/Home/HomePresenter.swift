import Foundation

@MainActor
final class HomePresenter: ObservableObject {
    @Published private(set) var viewState: HomeViewState

    private let interactor: HomeInteracting
    private let router: HomeRouting
    private let sessionStore: SessionStore?
    private let distanceFormatter = DistanceFormatter()

    private var hasLoaded = false
    private var isPaging = false
    private var isConfigurationBlocked = false
    private var nearbyStoreSummaries: [StoreSummary] = []
    private var realtimeDistanceStoreSummaries: [StoreSummary] = []

    init(
        interactor: HomeInteracting,
        router: HomeRouting,
        sessionStore: SessionStore? = nil
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore

        var initialState = HomeViewState()
        initialState.selectedCategory = HomeCategoryItem.all.first(where: { $0.id == "dessert" })
        self.viewState = initialState
    }

    func send(_ action: HomeAction) async {
        switch action {
        case .onAppear:
            reloadNotificationUnreadCount()
            guard !hasLoaded else { return }
            await loadHome(isRefresh: false)
        case .refreshRequested:
            reloadNotificationUnreadCount()
            guard !isConfigurationBlocked else { return }
            await loadHome(isRefresh: true)
        case .loginRequiredTapped:
            router.routeToAuth()
        case .notificationButtonTapped:
            router.routeToNotificationList()
        case .notificationUnreadCountChanged(let count):
            updateNotificationUnreadCount(count)
        case .notificationUnreadCountReloadRequested:
            reloadNotificationUnreadCount()
        case .locationTapped:
            router.routeToLocationPicker()
        case .currentLocationRequested:
            await useCurrentLocation()
        case .manualLocationSelectionTapped:
            router.routeToLocationSearch()
        case .selectedLocationSelected(let location):
            interactor.saveSelectedLocation(location)
            await loadHome(isRefresh: true)
        case .searchTextChanged(let text):
            viewState.searchText = text
        case .searchSubmitted:
            let query = viewState.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            viewState.searchText = query
            router.routeToSearch(query: query)
        case .popularKeywordTapped(let keyword):
            let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            viewState.searchText = query
            router.routeToSearch(query: query)
        case .categoryTapped(let categoryID):
            viewState.selectedCategory = viewState.categories.first(where: { $0.id == categoryID })
            guard !isConfigurationBlocked else { return }
            await loadHome(isRefresh: false)
        case .bannerTapped(let bannerID, let index):
            guard viewState.banners.indices.contains(index) else { return }
            let banner = viewState.banners[index]
            guard banner.id == bannerID else { return }
            router.routeToBanner(banner)
        case .nearbyStoreTabTapped(let tab):
            viewState.selectedNearbyStoreTab = tab
            applyNearbyStores()
        case .nearbyDistanceSortTapped:
            viewState.nearbyStoreSortOrder.toggle()
            applyNearbyStores()
        case .popularStoreTapped(let storeID), .nearbyStoreTapped(let storeID):
            router.routeToStoreDetail(storeID: storeID)
        case .nearbyStoreAppeared(let storeID):
            guard !isConfigurationBlocked else { return }
            await loadNextPageIfNeeded(triggeredBy: storeID)
        case .likeTapped(let storeID):
            guard !isConfigurationBlocked else { return }
            await toggleLike(for: storeID)
        }
    }

    private func loadHome(isRefresh: Bool) async {
        guard !isConfigurationBlocked else { return }
        guard sessionStore?.isAuthenticated != false else {
            applyAuthenticationRequiredState()
            return
        }

        if isRefresh || hasLoaded {
            viewState.isRefreshing = true
        } else {
            viewState.isLoading = true
        }
        viewState.errorMessage = nil
        viewState.emptyState = nil
        clearSectionMessages()

        do {
            let content = try await interactor.loadHome(category: selectedCategoryAPIValue)
            apply(content: content)
            hasLoaded = true
            isConfigurationBlocked = false
        } catch {
            if let homeError = error as? HomeFeedError,
               homeError.blocksRetry {
                isConfigurationBlocked = true
            }
            viewState.errorMessage = resolveErrorMessage(from: error)
            if viewState.popularStores.isEmpty && viewState.nearbyStores.isEmpty && viewState.banners.isEmpty {
                viewState.emptyState = makeFailureEmptyState(for: error)
            }
        }

        viewState.isLoading = false
        viewState.isRefreshing = false
    }

    private func loadNextPageIfNeeded(triggeredBy storeID: String) async {
        guard sessionStore?.isAuthenticated != false else {
            applyAuthenticationRequiredState()
            return
        }

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
            nearbyStoreSummaries.append(contentsOf: nextPage.items)
            realtimeDistanceStoreSummaries.append(contentsOf: nextPage.items)
            applyNearbyStores()
            viewState.nextCursor = nextPage.nextCursor
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func toggleLike(for storeID: String) async {
        guard sessionStore?.isAuthenticated != false else {
            applyAuthenticationRequiredState()
            return
        }

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

    private func useCurrentLocation() async {
        guard !isConfigurationBlocked else { return }
        guard sessionStore?.isAuthenticated != false else {
            applyAuthenticationRequiredState()
            return
        }

        viewState.errorMessage = nil

        switch await interactor.requestCurrentLocationForHome() {
        case .available:
            await loadHome(isRefresh: true)
        case .authorizationRequested:
            viewState.errorMessage = "위치 권한을 허용한 뒤 다시 시도해 주세요."
        case .permissionDenied:
            router.routeToLocationPermissionSettings()
        case .unavailable(let message):
            viewState.errorMessage = message
        }
    }

    private func apply(content: HomeContent) {
        viewState.locationLabel = content.locationLabel
        viewState.popularKeywords = content.popularKeywords
        viewState.banners = content.banners.map(makeBannerItem)
        viewState.popularStores = content.popularStores.map(makeStoreCardModel)
        nearbyStoreSummaries = content.nearbyStoresPage.items
        realtimeDistanceStoreSummaries = content.nearbyStoresPage.items
        applyNearbyStores()
        viewState.popularKeywordsSectionMessage = nil
        viewState.bannerSectionMessage = nil
        viewState.popularStoresSectionMessage = nil
        viewState.nearbyStoresSectionMessage = nearbyStoresFallbackMessage(from: content)
        viewState.nextCursor = content.nearbyStoresPage.nextCursor
        viewState.emptyState = nil
    }

    private func reloadNotificationUnreadCount() {
        let count = interactor.notificationUnreadCount()
        Logger(category: "NotificationBell").debugVerbose("[NotificationBell] unreadCount loaded count=\(count)")
        updateNotificationUnreadCount(count)
    }

    private func updateNotificationUnreadCount(_ count: Int) {
        let normalizedCount = max(0, count)
        viewState.notificationUnreadCount = normalizedCount
        Logger(category: "NotificationBell").debugVerbose("[NotificationBell] badge updated count=\(normalizedCount)")
    }

    private func applyAuthenticationRequiredState() {
        viewState.isLoading = false
        viewState.isRefreshing = false
        viewState.errorMessage = HomeFeedError.authenticationRequired.localizedDescription
        viewState.emptyState = makeFailureEmptyState(for: HomeFeedError.authenticationRequired)
        clearSectionMessages()
    }

    private func clearSectionMessages() {
        viewState.popularKeywordsSectionMessage = nil
        viewState.bannerSectionMessage = nil
        viewState.popularStoresSectionMessage = nil
        viewState.nearbyStoresSectionMessage = nil
    }

    private func applyLikeStatus(_ isLiked: Bool, to storeID: String) {
        nearbyStoreSummaries = nearbyStoreSummaries.map { updatedLikeSummary($0, storeID: storeID, isLiked: isLiked) }
        realtimeDistanceStoreSummaries = realtimeDistanceStoreSummaries.map { updatedLikeSummary($0, storeID: storeID, isLiked: isLiked) }
        viewState.popularStores = viewState.popularStores.map { updatedLikeModel($0, storeID: storeID, isLiked: isLiked) }
        viewState.nearbyStores = viewState.nearbyStores.map { updatedLikeModel($0, storeID: storeID, isLiked: isLiked) }
    }

    private func applyNearbyStores() {
        let sourceStores: [StoreSummary]
        switch viewState.selectedNearbyStoreTab {
        case .nearby:
            sourceStores = nearbyStoreSummaries
        case .realtimeDistance:
            sourceStores = realtimeDistanceStoreSummaries
        }

        let stores = sortedNearbyStores(
            sourceStores,
            tab: viewState.selectedNearbyStoreTab,
            sortOrder: viewState.nearbyStoreSortOrder
        )
        viewState.nearbyStores = stores.map(makeStoreCardModel)
    }

    private func sortedNearbyStores(
        _ stores: [StoreSummary],
        tab: HomeNearbyStoreTab,
        sortOrder: HomeNearbyStoreSortOrder
    ) -> [StoreSummary] {
        stores.sorted { lhs, rhs in
            let lhsKey = nearbySortKey(for: lhs, tab: tab)
            let rhsKey = nearbySortKey(for: rhs, tab: tab)

            switch (lhsKey, rhsKey) {
            case let (lhsKey?, rhsKey?):
                if lhsKey == rhsKey {
                    return lhs.name < rhs.name
                }

                return sortOrder == .nearest
                    ? lhsKey < rhsKey
                    : lhsKey > rhsKey
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.name < rhs.name
            }
        }
    }

    private func nearbySortKey(for store: StoreSummary, tab: HomeNearbyStoreTab) -> Double? {
        switch tab {
        case .nearby:
            return store.distanceMeters
        case .realtimeDistance:
            return store.distanceMeters
        }
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

    private func updatedLikeSummary(_ store: StoreSummary, storeID: String, isLiked: Bool) -> StoreSummary {
        guard store.id == storeID else {
            return store
        }

        let delta: Int
        switch (store.isLiked, isLiked) {
        case (true, false):
            delta = -1
        case (false, true):
            delta = 1
        default:
            delta = 0
        }

        return StoreSummary(
            id: store.id,
            category: store.category,
            name: store.name,
            closeTime: store.closeTime,
            imagePaths: store.imagePaths,
            isPicchelin: store.isPicchelin,
            isLiked: isLiked,
            likeCount: max(store.likeCount + delta, 0),
            hashTags: store.hashTags,
            totalRating: store.totalRating,
            totalOrderCount: store.totalOrderCount,
            totalReviewCount: store.totalReviewCount,
            longitude: store.longitude,
            latitude: store.latitude,
            distanceMeters: store.distanceMeters
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
        let tags = Array(normalizedTags(from: store).prefix(2))

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
            openTimeText: formattedCloseTime(from: store.closeTime),
            orderCountText: "\(store.totalOrderCount)회",
            tags: tags,
            isLiked: store.isLiked,
            isPickupAvailable: isPickupAvailable(for: store)
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

    private func formattedCloseTime(from closeTime: String?) -> String {
        guard let closeTime, !closeTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "-"
        }

        return closeTime
    }

    private func isPickupAvailable(for store: StoreSummary) -> Bool {
        guard let closeTime = store.closeTime else {
            return false
        }

        return !closeTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func makeEmptyState(for _: HomeContent) -> HomeEmptyState? {
        nil
    }

    private func nearbyStoresFallbackMessage(from content: HomeContent) -> String? {
        guard content.nearbyStoresPage.items.isEmpty,
              content.sectionMessages.nearbyStores != nil else {
            return nil
        }

        return "가까운 매장을 불러오지 못했어요. 잠시 후 다시 확인해 주세요."
    }

    private func makeFailureEmptyState(for error: Error) -> HomeEmptyState {
        if let homeError = error as? HomeFeedError {
            switch homeError {
            case .authenticationRequired:
                return HomeEmptyState(
                    title: "로그인이 필요해요",
                    message: "홈의 실시간 가게 정보와 찜 기능은 로그인 후 이용할 수 있어요.",
                    actionTitle: "로그인하러 가기",
                    requiresAuthentication: true
                )
            case .configurationRequired(let message):
                return HomeEmptyState(
                    title: "홈 정보를 불러오지 못했어요",
                    message: message,
                    actionTitle: nil
                )
            case .unavailable(let message):
                return HomeEmptyState(
                    title: "홈 정보를 불러오지 못했어요",
                    message: message,
                    actionTitle: "다시 불러오기"
                )
            }
        }

        return HomeEmptyState(
            title: "홈 정보를 불러오지 못했어요",
            message: resolveErrorMessage(from: error),
            actionTitle: "다시 불러오기"
        )
    }
}
