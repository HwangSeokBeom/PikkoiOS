import XCTest
@testable import Pikko

@MainActor
final class StoreDetailPresenterCartTests: XCTestCase {
    func testMenuIncrementUpdatesCartStoreAndStickySummary() async {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())
        let router = SpyStoreDetailRouter()
        let presenter = makePresenter(
            content: makeContent(storeID: "store-1", storeName: "새싹 카페"),
            cartStore: cartStore,
            router: router
        )

        await presenter.send(.onAppear)

        XCTAssertFalse(presenter.viewState.stickyCartSummary.isEnabled)
        XCTAssertEqual(presenter.viewState.stickyCartSummary.totalPriceText, "0원")

        await presenter.send(.menuIncrementTapped("menu-1"))
        await Task.yield()

        XCTAssertEqual(cartStore.currentStoreID, "store-1")
        XCTAssertEqual(cartStore.quantity(for: "menu-1", in: "store-1"), 1)
        XCTAssertEqual(presenter.viewState.menus.first?.quantity, 1)
        XCTAssertEqual(presenter.viewState.stickyCartSummary.itemCountText, "1")
        XCTAssertEqual(presenter.viewState.stickyCartSummary.totalPriceText, "4,500원")
        XCTAssertEqual(presenter.viewState.stickyCartSummary.buttonTitle, "장바구니 보기")
        XCTAssertTrue(presenter.viewState.stickyCartSummary.isEnabled)
    }

    func testMenuIncrementReplacesExistingOtherStoreCartAndShowsWarning() async {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())
        cartStore.setQuantity(
            2,
            menuID: "legacy-menu",
            menuName: "기존 메뉴",
            unitPrice: 3000,
            imagePath: nil,
            storeID: "store-legacy",
            storeName: "이전 가게"
        )

        let presenter = makePresenter(
            content: makeContent(storeID: "store-1", storeName: "새싹 카페"),
            cartStore: cartStore,
            router: SpyStoreDetailRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.menuIncrementTapped("menu-1"))
        await Task.yield()

        XCTAssertEqual(cartStore.currentStoreID, "store-1")
        XCTAssertEqual(cartStore.quantity(for: "legacy-menu", in: "store-legacy"), 0)
        XCTAssertEqual(cartStore.quantity(for: "menu-1", in: "store-1"), 1)
        XCTAssertEqual(
            presenter.viewState.errorMessage,
            "장바구니는 한 가게만 담을 수 있어요. 기존 장바구니를 현재 가게 기준으로 교체했어요."
        )
    }

    func testStickyCTATappedRoutesToCartWhenCartHasItems() async {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())
        let router = SpyStoreDetailRouter()
        let presenter = makePresenter(
            content: makeContent(storeID: "store-1", storeName: "새싹 카페"),
            cartStore: cartStore,
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.stickyCTATapped)

        XCTAssertNil(router.routedCartStoreID)

        await presenter.send(.menuIncrementTapped("menu-1"))
        await Task.yield()
        await presenter.send(.stickyCTATapped)

        XCTAssertEqual(router.routedCartStoreID, "store-1")
    }

    private func makePresenter(
        content: StoreDetailContent,
        cartStore: CartStore,
        router: SpyStoreDetailRouter
    ) -> StoreDetailPresenter {
        StoreDetailPresenter(
            interactor: StubStoreDetailInteractor(content: content),
            router: router,
            cartStore: cartStore
        )
    }

    private func makeContent(storeID: String, storeName: String) -> StoreDetailContent {
        StoreDetailContent(
            detail: StoreDetail(
                id: storeID,
                category: "카페",
                name: storeName,
                description: "테스트용 상세 설명",
                hashTags: [],
                openTime: "09:00",
                closeTime: "21:00",
                address: "서울 영등포구 테스트로 1",
                estimatedPickupMinutes: 15,
                parkingGuide: "주차 가능",
                imagePaths: [],
                isPicchelin: false,
                isLiked: false,
                likeCount: 0,
                totalReviewCount: 0,
                totalOrderCount: 0,
                totalRating: 4.5,
                owner: nil,
                longitude: 126.9,
                latitude: 37.5,
                menus: [
                    StoreMenu(
                        id: "menu-1",
                        storeID: storeID,
                        category: "커피",
                        name: "카페라떼",
                        description: "고소한 라떼",
                        originInformation: nil,
                        price: 4500,
                        isSoldOut: false,
                        tags: ["인기"],
                        imagePath: nil,
                        createdAt: nil,
                        updatedAt: nil
                    )
                ],
                createdAt: nil,
                updatedAt: nil
            ),
            reviewPage: CursorPage(items: [], nextCursor: nil),
            reviewRatings: [],
            distanceMeters: 120,
            warningMessage: nil
        )
    }
}

@MainActor
private struct StubStoreDetailInteractor: StoreDetailInteracting {
    let content: StoreDetailContent

    func loadInitialContent() async throws -> StoreDetailContent {
        content
    }

    func updateLikeStatus(isLiked: Bool) async throws -> Bool {
        isLiked
    }

    func deleteReview(reviewID: String) async throws {}
}

@MainActor
private final class SpyStoreDetailRouter: StoreDetailRouting {
    private(set) var routedDirectionsStoreName: String?
    private(set) var routedChatStoreID: String?
    private(set) var routedCartStoreID: String?
    private(set) var routedReviewContext: ReviewComposerContext?
    private(set) var authRouteRequested = false

    func routeToAuth() {
        authRouteRequested = true
    }

    func routeToDirections(
        storeName: String,
        address: String?,
        latitude: Double?,
        longitude: Double?
    ) {
        routedDirectionsStoreName = storeName
    }

    func routeToChat(storeID: String) {
        routedChatStoreID = storeID
    }

    func routeToCart(storeID: String) {
        routedCartStoreID = storeID
    }

    func routeToReviewComposer(context: ReviewComposerContext) {
        routedReviewContext = context
    }

    func clearPendingRoute() {}
}
