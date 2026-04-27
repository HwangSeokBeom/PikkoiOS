import XCTest
@testable import Pikko

@MainActor
final class HomePresenterTests: XCTestCase {
    func testHomePresenterBlocksRetryAfterConfigurationFailure() async {
        let interactor = StubHomeInteractor(
            loadHomeResult: .failure(
                HomeFeedError.configurationRequired(
                    message: "PIKKO_BASE_URL이 누락되었습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
                )
            )
        )
        let presenter = HomePresenter(
            interactor: interactor,
            router: SpyHomeRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.refreshRequested)
        await presenter.send(.categoryTapped("coffee"))

        XCTAssertEqual(interactor.loadHomeCallCount, 1)
        XCTAssertNil(presenter.viewState.emptyState?.actionTitle)
        XCTAssertEqual(
            presenter.viewState.emptyState?.message,
            "PIKKO_BASE_URL이 누락되었습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
        )
    }

    func testHomePresenterKeepsRenderableSectionsWhenOneSectionFails() async {
        let interactor = StubHomeInteractor(
            loadHomeResult: .success(
                HomeContent(
                    locationLabel: "현재 위치 주변",
                    popularKeywords: [],
                    banners: [],
                    popularStores: [],
                    nearbyStoresPage: CursorPage(items: [makeStoreSummary()], nextCursor: nil),
                    sectionMessages: HomeSectionMessages(
                        popularKeywords: nil,
                        banners: nil,
                        popularStores: "실시간 인기 맛집을 불러오지 못했어요.",
                        nearbyStores: nil
                    )
                )
            )
        )
        let presenter = HomePresenter(
            interactor: interactor,
            router: SpyHomeRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertNil(presenter.viewState.emptyState)
        XCTAssertEqual(presenter.viewState.nearbyStores.count, 1)
        XCTAssertNil(presenter.viewState.popularStoresSectionMessage)
    }

    func testHomePresenterKeepsHomeLayoutWhenContentLoadsEmpty() async {
        let interactor = StubHomeInteractor(
            loadHomeResult: .success(
                HomeContent(
                    locationLabel: "문래역, 영등포구",
                    popularKeywords: [],
                    banners: [],
                    popularStores: [],
                    nearbyStoresPage: CursorPage(items: [], nextCursor: nil)
                )
            )
        )
        let presenter = HomePresenter(
            interactor: interactor,
            router: SpyHomeRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertNil(presenter.viewState.emptyState)
        XCTAssertTrue(presenter.viewState.popularStores.isEmpty)
        XCTAssertTrue(presenter.viewState.nearbyStores.isEmpty)
    }

    func testNearbySortButtonKeepsNearbyTabAndTogglesSortOrder() async {
        let interactor = StubHomeInteractor(
            loadHomeResult: .success(
                makeHomeContent(
                    stores: [
                        makeStoreSummary(id: "far", name: "먼 가게", distanceMeters: 900),
                        makeStoreSummary(id: "near", name: "가까운 가게", distanceMeters: 120),
                        makeStoreSummary(id: "middle", name: "중간 가게", distanceMeters: 450),
                        makeStoreSummary(id: "unknown", name: "거리 미확인", distanceMeters: nil)
                    ]
                )
            )
        )
        let presenter = HomePresenter(
            interactor: interactor,
            router: SpyHomeRouter()
        )

        await presenter.send(.onAppear)
        XCTAssertEqual(presenter.viewState.selectedNearbyStoreTab, .nearby)
        XCTAssertEqual(presenter.viewState.nearbyStoreSortOrder, .nearest)
        XCTAssertEqual(presenter.viewState.nearbyStores.map(\.id), ["near", "middle", "far", "unknown"])

        await presenter.send(.nearbyDistanceSortTapped)

        XCTAssertEqual(presenter.viewState.selectedNearbyStoreTab, .nearby)
        XCTAssertEqual(presenter.viewState.nearbyStoreSortOrder, .farthest)
        XCTAssertEqual(presenter.viewState.nearbyDistanceSortTitle, "먼거리순")
        XCTAssertEqual(presenter.viewState.nearbyStores.map(\.id), ["far", "middle", "near", "unknown"])
    }

    func testRealtimeSortButtonKeepsRealtimeTabAndTogglesSortOrder() async {
        let presenter = HomePresenter(
            interactor: StubHomeInteractor(
                loadHomeResult: .success(
                    makeHomeContent(
                        stores: [
                            makeStoreSummary(id: "far", name: "먼 가게", distanceMeters: 900),
                            makeStoreSummary(id: "near", name: "가까운 가게", distanceMeters: 120)
                        ]
                    )
                )
            ),
            router: SpyHomeRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.nearbyStoreTabTapped(.realtimeDistance))
        await presenter.send(.nearbyDistanceSortTapped)

        XCTAssertEqual(presenter.viewState.selectedNearbyStoreTab, .realtimeDistance)
        XCTAssertEqual(presenter.viewState.nearbyStoreSortOrder, .farthest)
        XCTAssertEqual(presenter.viewState.nearbyStores.map(\.id), ["far", "near"])
    }

    func testNearbyTabTapPreservesSortOrder() async {
        let presenter = HomePresenter(
            interactor: StubHomeInteractor(
                loadHomeResult: .success(
                    makeHomeContent(
                        stores: [
                            makeStoreSummary(id: "far", name: "먼 가게", distanceMeters: 900),
                            makeStoreSummary(id: "near", name: "가까운 가게", distanceMeters: 120)
                        ]
                    )
                )
            ),
            router: SpyHomeRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.nearbyDistanceSortTapped)
        await presenter.send(.nearbyStoreTabTapped(.realtimeDistance))
        await presenter.send(.nearbyStoreTabTapped(.nearby))

        XCTAssertEqual(presenter.viewState.selectedNearbyStoreTab, .nearby)
        XCTAssertEqual(presenter.viewState.nearbyStoreSortOrder, .farthest)
        XCTAssertEqual(presenter.viewState.nearbyStores.map(\.id), ["far", "near"])
    }

    func testRealtimeTabTapPreservesSortOrder() async {
        let presenter = HomePresenter(
            interactor: StubHomeInteractor(
                loadHomeResult: .success(
                    makeHomeContent(
                        stores: [
                            makeStoreSummary(id: "far", name: "먼 가게", distanceMeters: 900),
                            makeStoreSummary(id: "near", name: "가까운 가게", distanceMeters: 120)
                        ]
                    )
                )
            ),
            router: SpyHomeRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.nearbyDistanceSortTapped)
        await presenter.send(.nearbyStoreTabTapped(.realtimeDistance))

        XCTAssertEqual(presenter.viewState.selectedNearbyStoreTab, .realtimeDistance)
        XCTAssertEqual(presenter.viewState.nearbyStoreSortOrder, .farthest)
        XCTAssertEqual(presenter.viewState.nearbyStores.map(\.id), ["far", "near"])
    }

    func testHomePresenterSkipsHomeAPIsWhenSessionIsUnauthenticated() async {
        let interactor = StubHomeInteractor(
            loadHomeResult: .failure(NetworkError.transport)
        )
        let presenter = HomePresenter(
            interactor: interactor,
            router: SpyHomeRouter(),
            sessionStore: makeUnauthenticatedSessionStore()
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(interactor.loadHomeCallCount, 0)
        XCTAssertEqual(presenter.viewState.errorMessage, "로그인이 필요합니다. 다시 로그인해 주세요.")
        XCTAssertTrue(presenter.viewState.emptyState?.requiresAuthentication == true)
    }

    func testHomePresenterDoesNotRouteSearchWhenQueryIsBlank() async {
        let router = SpyHomeRouter()
        let presenter = HomePresenter(
            interactor: StubHomeInteractor(
                loadHomeResult: .success(
                    HomeContent(
                        locationLabel: "문래역, 영등포구",
                        popularKeywords: [],
                        banners: [],
                        popularStores: [],
                        nearbyStoresPage: CursorPage(items: [], nextCursor: nil)
                    )
                )
            ),
            router: router
        )

        await presenter.send(.searchTextChanged("   "))
        await presenter.send(.searchSubmitted)

        XCTAssertNil(router.routedSearchQuery)
    }

    func testHomePresenterRoutesTrimmedSearchQuery() async {
        let router = SpyHomeRouter()
        let presenter = HomePresenter(
            interactor: StubHomeInteractor(
                loadHomeResult: .success(
                    HomeContent(
                        locationLabel: "문래역, 영등포구",
                        popularKeywords: [],
                        banners: [],
                        popularStores: [],
                        nearbyStoresPage: CursorPage(items: [], nextCursor: nil)
                    )
                )
            ),
            router: router
        )

        await presenter.send(.searchTextChanged("  베이커리  "))
        await presenter.send(.searchSubmitted)

        XCTAssertEqual(router.routedSearchQuery, "베이커리")
        XCTAssertEqual(presenter.viewState.searchText, "베이커리")
    }

    func testBannerTapRoutesInjectedBannerEvenWhenIDsMatch() async {
        let router = SpyHomeRouter()
        let presenter = HomePresenter(
            interactor: StubHomeInteractor(
                loadHomeResult: .success(
                    HomeContent(
                        locationLabel: "문래역, 영등포구",
                        popularKeywords: [],
                        banners: [
                            Banner(
                                id: "WEBVIEW:/event",
                                name: "banner1",
                                imagePath: "/banner1.png",
                                payloadType: "WEBVIEW",
                                payloadValue: "/banner1"
                            ),
                            Banner(
                                id: "WEBVIEW:/event",
                                name: "banner2",
                                imagePath: "/banner2.png",
                                payloadType: "WEBVIEW",
                                payloadValue: "/banner2"
                            )
                        ],
                        popularStores: [],
                        nearbyStoresPage: CursorPage(items: [], nextCursor: nil)
                    )
                )
            ),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.bannerTapped(id: presenter.viewState.banners[1].id, index: 1))

        XCTAssertEqual(router.routedBanner?.title, "banner2")
        XCTAssertEqual(router.routedBanner?.payloadValue, "/banner2")
    }

    private func makeStoreSummary(
        id: String = "store-1",
        name: String = "픽코 베이커리",
        distanceMeters: Double? = 120
    ) -> StoreSummary {
        StoreSummary(
            id: id,
            category: "디저트",
            name: name,
            closeTime: "20:00",
            imagePaths: [],
            isPicchelin: false,
            isLiked: false,
            likeCount: 0,
            hashTags: [],
            totalRating: 4.5,
            totalOrderCount: 10,
            totalReviewCount: 3,
            longitude: nil,
            latitude: nil,
            distanceMeters: distanceMeters
        )
    }

    private func makeHomeContent(stores: [StoreSummary]) -> HomeContent {
        HomeContent(
            locationLabel: "문래역, 영등포구",
            popularKeywords: [],
            banners: [],
            popularStores: [],
            nearbyStoresPage: CursorPage(items: stores, nextCursor: nil)
        )
    }

    private func makeUnauthenticatedSessionStore() -> SessionStore {
        SessionStore(
            tokenStore: StubHomeTokenStore(),
            userDefaultsStore: UserDefaultsStore(userDefaults: UserDefaults(suiteName: #function + UUID().uuidString)!)
        )
    }
}

private actor StubHomeTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}

@MainActor
final class StoreListPresenterTests: XCTestCase {
    func testStoreListPresenterShowsEmptyStateForSearchResults() async {
        let presenter = StoreListPresenter(
            mode: .search(query: "베이커리"),
            interactor: StubStoreListInteractor(
                initialPage: CursorPage(items: [], nextCursor: nil),
                nextPage: CursorPage(items: [], nextCursor: nil),
                updateLikeStatusResult: false
            ),
            router: SpyStoreListRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.showsEmptyState)
        XCTAssertEqual(presenter.viewState.emptyStateTitle, "검색 결과가 없어요")
        XCTAssertEqual(presenter.viewState.emptyStateMessage, "다른 검색어로 다시 찾아보세요.")
    }

    func testStoreListPresenterRemovesStoreAfterUnlikeInLikedMode() async {
        let presenter = StoreListPresenter(
            mode: .liked(category: nil),
            interactor: StubStoreListInteractor(
                initialPage: CursorPage(items: [makeLikedStoreSummary()], nextCursor: nil),
                nextPage: CursorPage(items: [], nextCursor: nil),
                updateLikeStatusResult: false
            ),
            router: SpyStoreListRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.likeTapped("liked-store"))

        XCTAssertTrue(presenter.viewState.stores.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyStateTitle, "찜한 가게가 없어요")
    }

    private func makeLikedStoreSummary() -> StoreSummary {
        StoreSummary(
            id: "liked-store",
            category: "디저트",
            name: "찜한 가게",
            closeTime: "20:00",
            imagePaths: ["/data/stores/main.jpg"],
            isPicchelin: false,
            isLiked: true,
            likeCount: 4,
            hashTags: ["#픽업"],
            totalRating: 4.8,
            totalOrderCount: 12,
            totalReviewCount: 5,
            longitude: nil,
            latitude: nil,
            distanceMeters: 200
        )
    }
}

@MainActor
private final class StubHomeInteractor: HomeInteracting {
    private(set) var loadHomeCallCount = 0
    private let loadHomeResult: Result<HomeContent, Error>

    init(loadHomeResult: Result<HomeContent, Error>) {
        self.loadHomeResult = loadHomeResult
    }

    func loadHome(category: String?) async throws -> HomeContent {
        loadHomeCallCount += 1
        return try loadHomeResult.get()
    }

    func loadMoreNearbyStores(category: String?, nextCursor: String) async throws -> CursorPage<StoreSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool {
        isLiked
    }
}

@MainActor
private final class SpyHomeRouter: HomeRouting {
    private(set) var routedSearchQuery: String?
    private(set) var routedBanner: HomeBannerItem?

    func routeToAuth() {}
    func routeToLocationPicker() {}
    func routeToSearch(query: String) { routedSearchQuery = query }
    func routeToBanner(_ banner: HomeBannerItem) { routedBanner = banner }
    func routeToStoreDetail(storeID: String) {}
    func clearPendingRoute() {}
}

@MainActor
private struct StubStoreListInteractor: StoreListInteracting {
    let initialPage: CursorPage<StoreSummary>
    let nextPage: CursorPage<StoreSummary>
    let updateLikeStatusResult: Bool

    func loadInitialStores() async throws -> CursorPage<StoreSummary> {
        initialPage
    }

    func loadMoreStores(nextCursor: String) async throws -> CursorPage<StoreSummary> {
        _ = nextCursor
        return nextPage
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool {
        _ = storeID
        _ = isLiked
        return updateLikeStatusResult
    }
}

@MainActor
private final class SpyStoreListRouter: StoreListRouting {
    private(set) var routedStoreID: String?

    func routeToStoreDetail(storeID: String) {
        routedStoreID = storeID
    }

    func clearPendingRoute() {}
}
