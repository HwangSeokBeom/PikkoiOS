import XCTest
@testable import Pikko

@MainActor
final class OrderFeatureTests: XCTestCase {
    func testFetchOrdersSuccessReflectsOrders() async {
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(
                        CursorPage(
                            items: [makeOrder(id: "order-1"), makeOrder(id: "order-2", status: .ready)],
                            nextCursor: nil
                        )
                    )
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.orders.count, 2)
        XCTAssertEqual(presenter.viewState.orders.first?.storeName, "새싹 카페")
        XCTAssertEqual(presenter.viewState.orders.last?.statusTitle, OrderStatus.ready.displayTitle)
        XCTAssertFalse(presenter.viewState.isInitialLoading)
        XCTAssertNil(presenter.viewState.emptyState)
    }

    func testFetchOrdersFailureReflectsErrorState() async {
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .failure(.unavailable(message: "주문 내역을 가져오지 못했어요."))
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.orders.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyState?.title, "주문 내역을 불러오지 못했어요")
        XCTAssertEqual(presenter.viewState.emptyState?.message, "주문 내역을 가져오지 못했어요.")
    }

    func testPaginationPreventsDuplicateAppend() async {
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [
                .success(
                    CursorPage(
                        items: [makeOrder(id: "order-1"), makeOrder(id: "order-2")],
                        nextCursor: "cursor-1"
                    )
                ),
                .success(
                    CursorPage(
                        items: [makeOrder(id: "order-2"), makeOrder(id: "order-3", storeName: "픽코 샐러드")],
                        nextCursor: nil
                    )
                )
            ]
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)
        await presenter.send(.orderAppeared("order-2"))
        await presenter.send(.orderAppeared("order-3"))

        let fetchRequests = await interactor.fetchRequests()
        XCTAssertEqual(fetchRequests.count, 2)
        XCTAssertEqual(presenter.viewState.orders.map(\.id), ["order-1", "order-2", "order-3"])
        XCTAssertFalse(presenter.viewState.canLoadMore)
    }

    func testOrderTapRoutesToDetail() async {
        let router = SpyOrderRouter()
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [.success(CursorPage(items: [makeOrder(id: "order-1")], nextCursor: nil))]
            ),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.orderTapped("order-1"))

        XCTAssertEqual(router.routedOrderIDs, ["order-1"])
    }

    func testHighlightedOrderAutoRoutesToDetail() async {
        var initialState = makeInitialState()
        initialState.highlightedOrderID = "order-2"

        let router = SpyOrderRouter()
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: initialState,
                fetchResults: [.success(CursorPage(items: [makeOrder(id: "order-1"), makeOrder(id: "order-2")], nextCursor: nil))]
            ),
            router: router
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(router.routedOrderIDs, ["order-2"])
        XCTAssertEqual(presenter.viewState.orders.first(where: { $0.id == "order-2" })?.isHighlighted, true)
    }

    func testUnauthenticatedInitialStateSkipsOrderFetchAndShowsLoginPrompt() async {
        let interactor = SpyOrderInteractor(
            initialState: makeUnauthenticatedInitialState(),
            fetchResults: [.success(CursorPage(items: [makeOrder(id: "order-1")], nextCursor: nil))]
        )
        let presenter = OrderPresenter(
            interactor: interactor,
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        let fetchRequests = await interactor.fetchRequests()
        XCTAssertTrue(fetchRequests.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyState?.title, "로그인이 필요해요")
        XCTAssertTrue(presenter.viewState.requiresAuthentication)
    }

    private func makeInitialState() -> OrderViewState {
        var state = OrderViewState()
        state.isInitialLoading = true
        return state
    }

    private func makeUnauthenticatedInitialState() -> OrderViewState {
        var state = OrderViewState()
        state.emptyState = OrderEmptyState(
            title: "로그인이 필요해요",
            message: "주문 내역과 픽업 진행 상황은 로그인 후 확인할 수 있어요.",
            actionTitle: "로그인하기",
            requiresAuthentication: true
        )
        state.requiresAuthentication = true
        return state
    }

    private func makeOrder(
        id: String,
        storeName: String = "새싹 카페",
        status: OrderStatus = .preparing
    ) -> OrderSummary {
        OrderSummary(
            id: id,
            orderCode: "D-\(id)",
            storeID: "store-\(id)",
            storeName: storeName,
            storeImagePath: nil,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            totalAmount: 12_200,
            itemSummaries: [
                OrderItemSummary(
                    id: "menu-\(id)",
                    menuName: "카페라떼",
                    quantity: 1,
                    imagePath: nil,
                    unitPriceAmount: 4_500
                )
            ],
            pickupTime: Date(timeIntervalSince1970: 1_710_000_600),
            reviewID: nil,
            reviewRating: nil
        )
    }
}

@MainActor
private struct SpyOrderInteractor: OrderInteracting {
    let initialState: OrderViewState
    let fetchResults: [Result<CursorPage<OrderSummary>, OrderFeatureError>]

    private let recorder = OrderFetchRecorder()

    func loadInitialState() async -> OrderViewState {
        initialState
    }

    func fetchOrders(cursor: String?, filter: OrderListFilter) async throws -> CursorPage<OrderSummary> {
        let index = await recorder.append(cursor: cursor, filter: filter)
        let result = fetchResults[min(index, fetchResults.count - 1)]
        switch result {
        case .success(let page):
            return page
        case .failure(let error):
            throw error
        }
    }

    func fetchRequests() async -> [OrderFetchRequest] {
        await recorder.requests
    }
}

private struct OrderFetchRequest: Equatable {
    let cursor: String?
    let filter: OrderListFilter
}

private actor OrderFetchRecorder {
    private(set) var requests: [OrderFetchRequest] = []

    func append(cursor: String?, filter: OrderListFilter) -> Int {
        requests.append(OrderFetchRequest(cursor: cursor, filter: filter))
        return requests.count - 1
    }
}

@MainActor
private final class SpyOrderRouter: OrderRouting {
    private(set) var routedOrderIDs: [String] = []
    private(set) var authRouteCount = 0
    private(set) var exploreRouteCount = 0

    func routeToOrderDetail(orderID: String) {
        routedOrderIDs.append(orderID)
    }

    func routeToAuth() {
        authRouteCount += 1
    }

    func dismissAuth() {}

    func routeToExploreHome() {
        exploreRouteCount += 1
    }

    func clearPendingRoute() {}
}
