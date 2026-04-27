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
        XCTAssertFalse(presenter.viewState.orders.first?.canCancel ?? true)
        XCTAssertFalse(presenter.viewState.isInitialLoading)
        XCTAssertNil(presenter.viewState.emptyState)
    }

    func testOrderListItemDisplayTextReflectsSummary() async {
        let order = makeOrder(
            id: "order-1",
            itemSummaries: [
                OrderItemSummary(
                    id: "menu-1",
                    menuName: "카페라떼",
                    quantity: 2,
                    imagePath: nil,
                    unitPriceAmount: 4_500
                ),
                OrderItemSummary(
                    id: "menu-2",
                    menuName: "휘낭시에",
                    quantity: 1,
                    imagePath: nil,
                    unitPriceAmount: 3_200
                )
            ]
        )
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [.success(CursorPage(items: [order], nextCursor: nil))]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        let item = presenter.viewState.orders.first
        XCTAssertEqual(item?.storeName, "새싹 카페")
        XCTAssertEqual(item?.primaryItemText, "카페라떼 외 2개")
        XCTAssertEqual(item?.totalPriceText, CurrencyFormatter().string(from: order.totalAmount))
        XCTAssertEqual(item?.createdAtText, DateParser().string(from: order.createdAt, format: "M월 d일 a h:mm"))
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

    func testPendingOrderCanBeCancelledFromList() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending)
        let cancelledDetail = makeDetail(order: pendingOrder, status: .cancelled)
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [.success(CursorPage(items: [pendingOrder], nextCursor: nil))],
                cancelResults: ["D-order-1": .success(cancelledDetail)]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)
        XCTAssertTrue(presenter.viewState.orders.first?.canCancel == true)

        await presenter.send(.cancelConfirmed("order-1"))

        XCTAssertEqual(presenter.viewState.orders.first?.statusTitle, OrderStatus.cancelled.displayTitle)
        XCTAssertEqual(presenter.viewState.successMessage, "주문이 취소되었어요.")
        XCTAssertFalse(presenter.viewState.orders.first?.canCancel ?? true)
        XCTAssertTrue(presenter.viewState.cancellingOrderIDs.isEmpty)
    }

    func testCancelledOrderDisappearsFromActiveFilter() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending)
        let cancelledDetail = makeDetail(order: pendingOrder, status: .cancelled)
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [.success(CursorPage(items: [pendingOrder], nextCursor: nil))],
                cancelResults: ["D-order-1": .success(cancelledDetail)]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.filterTapped(.active))
        await presenter.send(.cancelConfirmed("order-1"))

        XCTAssertTrue(presenter.viewState.orders.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyState?.title, "선택한 상태의 주문이 없어요")
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

    func testAuthenticationFailureShowsAuthStateInsteadOfEmptyOrderState() async {
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [.failure(.authenticationRequired)]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.orders.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyState?.title, "로그인이 필요해요")
        XCTAssertTrue(presenter.viewState.requiresAuthentication)
    }

    func testRepositoryReturnsLocalFallbackOrderWhenServerFetchFails() async throws {
        let localSnapshotStore = makeLocalSnapshotStore()
        let repository = makeRepository(
            remoteDataSource: StubOrderRemoteDataSource(
                fetchOrdersResult: .failure(NetworkError.transport),
                createOrderResult: .success(makeCreatedOrderResponse())
            ),
            localSnapshotStore: localSnapshotStore
        )

        _ = try await repository.createOrder(makeSubmission())
        let page = try await repository.fetchOrders(cursor: nil, filter: nil)

        XCTAssertEqual(page.items.map(\.id), ["order-1"])
        XCTAssertEqual(page.items.first?.storeName, "새싹 카페")
        XCTAssertEqual(page.items.first?.status, .pending)
    }

    func testRepositoryDeduplicatesRemoteOrderAndLocalFallbackOrder() async throws {
        let localSnapshotStore = makeLocalSnapshotStore()
        let repository = makeRepository(
            remoteDataSource: StubOrderRemoteDataSource(
                fetchOrdersResult: .success(
                    OrderListResponseDTO(data: [makeRemoteOrderDTO(orderID: "order-1", orderCode: "D123456")])
                ),
                createOrderResult: .success(makeCreatedOrderResponse())
            ),
            localSnapshotStore: localSnapshotStore
        )

        _ = try await repository.createOrder(makeSubmission())
        let page = try await repository.fetchOrders(cursor: nil, filter: nil)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.id, "order-1")
        XCTAssertEqual(page.items.first?.status, .preparing)
    }

    func testRepositoryDoesNotHideAuthenticationFailureBehindLocalFallback() async throws {
        let localSnapshotStore = makeLocalSnapshotStore()
        let repository = makeRepository(
            remoteDataSource: StubOrderRemoteDataSource(
                fetchOrdersResult: .failure(NetworkError.refreshTokenExpired),
                createOrderResult: .success(makeCreatedOrderResponse())
            ),
            localSnapshotStore: localSnapshotStore
        )

        _ = try await repository.createOrder(makeSubmission())

        do {
            _ = try await repository.fetchOrders(cursor: nil, filter: nil)
            XCTFail("Expected authentication failure")
        } catch let error as NetworkError {
            XCTAssertTrue(error.isAuthenticationFailure)
        }
    }

    func testRepositoryCancelsUnpaidLocalPendingOrderWithoutStatusUpdateAPI() async throws {
        let localSnapshotStore = makeLocalSnapshotStore()
        let remoteDataSource = StubOrderRemoteDataSource(
            fetchOrdersResult: .failure(NetworkError.transport),
            createOrderResult: .success(makeCreatedOrderResponse())
        )
        let repository = makeRepository(
            remoteDataSource: remoteDataSource,
            localSnapshotStore: localSnapshotStore
        )

        _ = try await repository.createOrder(makeSubmission())
        let detail = try await repository.cancelOrder(orderCode: "D123456")
        let page = try await repository.fetchOrders(cursor: nil, filter: nil)

        XCTAssertEqual(detail.status, .cancelled)
        XCTAssertEqual(page.items.first?.status, .cancelled)
        XCTAssertTrue(remoteDataSource.updateStatusRequests.isEmpty)
    }

    func testRepositoryUsesStatusUpdateAPIForRemoteOrderCancellation() async throws {
        let localSnapshotStore = makeLocalSnapshotStore()
        let remoteDataSource = StubOrderRemoteDataSource(
            fetchOrdersResult: .success(
                OrderListResponseDTO(data: [makeRemoteOrderDTO(orderID: "order-1", orderCode: "D123456")])
            ),
            createOrderResult: .success(makeCreatedOrderResponse())
        )
        let repository = makeRepository(
            remoteDataSource: remoteDataSource,
            localSnapshotStore: localSnapshotStore
        )

        let detail = try await repository.cancelOrder(orderCode: "D123456")

        XCTAssertEqual(detail.status, .cancelled)
        XCTAssertEqual(remoteDataSource.updateStatusRequests, [
            OrderStatusUpdateRequest(orderCode: "D123456", nextStatus: "CANCELLED")
        ])
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
        status: OrderStatus = .preparing,
        itemSummaries: [OrderItemSummary]? = nil
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
            itemSummaries: itemSummaries ?? [
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

    private func makeDetail(order: OrderSummary, status: OrderStatus) -> OrderDetail {
        OrderDetail(
            orderID: order.id,
            orderCode: order.orderCode,
            storeID: order.storeID,
            storeName: order.storeName,
            storeCategory: nil,
            storeCloseTime: nil,
            storeImagePath: order.storeImagePath,
            status: status,
            createdAt: order.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_710_000_120),
            paidAt: nil,
            pickupTime: order.pickupTime,
            totalAmount: order.totalAmount,
            items: order.itemSummaries,
            timeline: [
                OrderStatusTimelineEntry(id: "pending", status: .pending, completed: true, changedAt: order.createdAt),
                OrderStatusTimelineEntry(id: "cancelled", status: .cancelled, completed: status == .cancelled, changedAt: Date(timeIntervalSince1970: 1_710_000_120))
            ],
            paymentSummary: nil,
            userMemo: nil,
            reviewRating: nil
        )
    }

    private func makeRepository(
        remoteDataSource: StubOrderRemoteDataSource,
        localSnapshotStore: OrderLocalSnapshotStore
    ) -> OrderRepositoryImpl {
        OrderRepositoryImpl(
            remoteDataSource: remoteDataSource,
            checkoutMapper: CheckoutMapper(),
            mapper: OrderMapper(fileURLResolver: StubOrderAuthorizedFileURLResolver()),
            localSnapshotStore: localSnapshotStore
        )
    }

    private func makeLocalSnapshotStore() -> OrderLocalSnapshotStore {
        let suiteName = #function + UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return OrderLocalSnapshotStore(
            store: UserDefaultsStore(userDefaults: userDefaults),
            storageKey: "test.order.localSnapshots"
        )
    }

    private func makeSubmission() -> CheckoutOrderSubmission {
        CheckoutOrderSubmission(
            draft: CheckoutDraft(
                storeID: "store-1",
                storeName: "새싹 카페",
                items: [
                    CheckoutDraftLineItem(
                        menuID: "menu-1",
                        menuName: "카페라떼",
                        imagePath: "/menus/latte.png",
                        optionSummaryText: nil,
                        unitPriceAmount: 4_500,
                        unitPriceText: "4,500원",
                        quantity: 1,
                        subtotalAmount: 4_500,
                        subtotalText: "4,500원"
                    )
                ],
                itemCount: 1,
                subtotalAmount: 4_500,
                subtotalText: "4,500원"
            ),
            address: .placeholder,
            paymentMethod: .card,
            coupon: nil,
            pickupMemo: "얼음 적게"
        )
    }

    private func makeCreatedOrderResponse() -> OrderCreateResponseDTO {
        OrderCreateResponseDTO(
            orderID: "order-1",
            orderCode: "D123456",
            totalPrice: 4_500,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000),
            paymentURL: nil,
            redirectURL: nil,
            paymentToken: nil
        )
    }

    private func makeRemoteOrderDTO(orderID: String, orderCode: String) -> OrderWithStatusResponseDTO {
        OrderWithStatusResponseDTO(
            orderID: orderID,
            orderCode: orderCode,
            totalPrice: 4_500,
            review: nil,
            store: StoreSummaryDTOOrder(
                id: "store-1",
                category: "커피",
                name: "새싹 카페",
                close: "21:00",
                storeImageURLs: []
            ),
            orderMenuList: [
                OrderMenuQuantityResponseDTO(
                    menu: MenuResponseDTOOrder(
                        id: "menu-1",
                        category: "커피",
                        name: "카페라떼",
                        detailDescription: nil,
                        price: 4_500,
                        tags: [],
                        menuImageURL: nil
                    ),
                    quantity: 1
                )
            ],
            currentOrderStatus: "IN_PROGRESS",
            orderStatusTimeline: [
                OrderStatusTimelineResponseDTO(
                    status: "IN_PROGRESS",
                    completed: true,
                    changedAt: "2024-03-09T16:00:00Z"
                )
            ],
            paidAt: nil,
            createdAt: "2024-03-09T16:00:00Z",
            updatedAt: "2024-03-09T16:00:00Z"
        )
    }
}

private final class StubOrderRemoteDataSource: OrderRemoteDataSourceProtocol, @unchecked Sendable {
    let fetchOrdersResult: Result<OrderListResponseDTO, Error>
    let createOrderResult: Result<OrderCreateResponseDTO, Error>
    private(set) var updateStatusRequests: [OrderStatusUpdateRequest] = []

    init(
        fetchOrdersResult: Result<OrderListResponseDTO, Error>,
        createOrderResult: Result<OrderCreateResponseDTO, Error>
    ) {
        self.fetchOrdersResult = fetchOrdersResult
        self.createOrderResult = createOrderResult
    }

    func fetchOrders(cursor: String?, filter: String?) async throws -> OrderListResponseDTO {
        _ = cursor
        _ = filter
        return try fetchOrdersResult.get()
    }

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentResponseDTO {
        _ = orderCode
        throw NetworkError.notFound(message: "영수증 없음")
    }

    func validatePayment(impUID: String) async throws -> ReceiptOrderResponseDTO {
        _ = impUID
        throw NetworkError.transport
    }

    func validatePrice(_ request: CheckoutPriceValidationRequestDTO) async throws -> CheckoutPriceValidationResponseDTO {
        _ = request
        return CheckoutPriceValidationResponseDTO(validatedTotalPrice: 0, issues: [], message: nil)
    }

    func createOrder(_ request: OrderCreateRequestDTO) async throws -> OrderCreateResponseDTO {
        _ = request
        return try createOrderResult.get()
    }

    func updateOrderStatus(orderCode: String, nextStatus: String) async throws {
        updateStatusRequests.append(OrderStatusUpdateRequest(orderCode: orderCode, nextStatus: nextStatus))
    }
}

private struct OrderStatusUpdateRequest: Equatable {
    let orderCode: String
    let nextStatus: String
}

private struct StubOrderAuthorizedFileURLResolver: AuthorizedFileURLResolving {
    func resolveURL(from path: String) throws -> URL {
        URL(string: "https://example.com\(path)")!
    }

    func resolveOptionalURL(from path: String?) throws -> URL? {
        guard let path else { return nil }
        return try resolveURL(from: path)
    }
}

@MainActor
private struct SpyOrderInteractor: OrderInteracting {
    let initialState: OrderViewState
    let fetchResults: [Result<CursorPage<OrderSummary>, OrderFeatureError>]
    var cancelResults: [String: Result<OrderDetail, OrderFeatureError>] = [:]

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

    func cancelOrder(orderCode: String) async throws -> OrderDetail {
        guard let result = cancelResults[orderCode] else {
            throw OrderFeatureError.unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
        }

        switch result {
        case .success(let detail):
            return detail
        case .failure(let error):
            throw error
        }
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
