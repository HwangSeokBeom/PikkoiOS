import XCTest
@testable import Pikko

@MainActor
final class OrderDetailFeatureTests: XCTestCase {
    func testFetchOrderDetailSuccessReflectsState() async {
        let presenter = OrderDetailPresenter(
            initialOrderID: "order-1",
            interactor: SpyOrderDetailInteractor(
                initialState: makeInitialState(orderID: "order-1"),
                fetchResult: .success(makeDetail(status: .ready))
            ),
            router: SpyOrderDetailRouter(),
            mapper: OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver())
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.hasLoadedContent)
        XCTAssertEqual(presenter.viewState.storeName, "새싹 카페")
        XCTAssertEqual(presenter.viewState.statusTitle, OrderStatus.ready.displayTitle)
        XCTAssertEqual(presenter.viewState.items.count, 2)
        XCTAssertEqual(presenter.viewState.items.first?.name, "카페라떼")
        XCTAssertEqual(presenter.viewState.items.first?.quantityText, "2개")
        XCTAssertEqual(presenter.viewState.items.first?.priceText, OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver()).currencyText(for: 4_500))
        XCTAssertNil(presenter.viewState.emptyState)
    }

    func testPendingPaidOrderShowsCancelButtonButCannotExecuteWithoutServerCancelAPI() async {
        let presenter = OrderDetailPresenter(
            initialOrderID: "order-1",
            interactor: SpyOrderDetailInteractor(
                initialState: makeInitialState(orderID: "order-1"),
                fetchResult: .success(makeDetail(status: .pending))
            ),
            router: SpyOrderDetailRouter(),
            mapper: OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver())
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.orderStatus, .pending)
        XCTAssertTrue(presenter.viewState.canCancelOrder)
        XCTAssertFalse(presenter.viewState.canExecuteCancelOrder)
        XCTAssertEqual(
            presenter.viewState.cancelDisabledReasonText,
            "결제 취소 API가 필요해요. 매장에 문의해 주세요."
        )
    }

    func testCompletedOrderHidesCancelAvailability() async {
        let presenter = OrderDetailPresenter(
            initialOrderID: "order-1",
            interactor: SpyOrderDetailInteractor(
                initialState: makeInitialState(orderID: "order-1"),
                fetchResult: .success(makeDetail(status: .completed))
            ),
            router: SpyOrderDetailRouter(),
            mapper: OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver())
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.orderStatus, .completed)
        XCTAssertFalse(presenter.viewState.canCancelOrder)
    }

    func testCancelConfirmedShowsPolicyMessageWithoutCallingUnsupportedServerPath() async {
        let presenter = OrderDetailPresenter(
            initialOrderID: "order-1",
            interactor: SpyOrderDetailInteractor(
                initialState: makeInitialState(orderID: "order-1"),
                fetchResult: .success(makeDetail(status: .pending)),
                cancelResult: .failure(.unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요."))
            ),
            router: SpyOrderDetailRouter(),
            mapper: OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver())
        )

        await presenter.send(.onAppear)
        await presenter.send(.cancelConfirmed)

        XCTAssertEqual(presenter.viewState.orderStatus, .pending)
        XCTAssertFalse(presenter.viewState.isCancelling)
        XCTAssertTrue(presenter.viewState.canCancelOrder)
        XCTAssertFalse(presenter.viewState.canExecuteCancelOrder)
        XCTAssertEqual(
            presenter.viewState.cancelErrorMessage,
            "결제 취소 API가 필요해요. 매장에 문의해 주세요."
        )
    }

    func testFetchOrderDetailFailureReflectsRetryState() async {
        let presenter = OrderDetailPresenter(
            initialOrderID: "order-1",
            interactor: SpyOrderDetailInteractor(
                initialState: makeInitialState(orderID: "order-1"),
                fetchResult: .failure(.unavailable(message: "주문 상세를 가져오지 못했어요."))
            ),
            router: SpyOrderDetailRouter(),
            mapper: OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver())
        )

        await presenter.send(.onAppear)

        XCTAssertFalse(presenter.viewState.hasLoadedContent)
        XCTAssertEqual(presenter.viewState.emptyState?.title, "주문 상세를 불러오지 못했어요")
        XCTAssertEqual(presenter.viewState.emptyState?.message, "주문 상세를 가져오지 못했어요.")
    }

    func testFetchOrderDetailNotFoundShowsOrderPropagationMessage() async {
        let presenter = OrderDetailPresenter(
            initialOrderID: "order-1",
            interactor: SpyOrderDetailInteractor(
                initialState: makeInitialState(orderID: "order-1"),
                fetchResult: .failure(.notFound)
            ),
            router: SpyOrderDetailRouter(),
            mapper: OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver())
        )

        await presenter.send(.onAppear)

        XCTAssertFalse(presenter.viewState.hasLoadedContent)
        XCTAssertEqual(presenter.viewState.emptyState?.title, "주문 반영 대기 중")
        XCTAssertEqual(presenter.viewState.emptyState?.message, "주문이 접수되었습니다. 목록 반영까지 잠시 걸릴 수 있습니다.")
        XCTAssertEqual(presenter.viewState.emptyState?.actionTitle, "다시 확인")
    }

    private func makeInitialState(orderID: String) -> OrderDetailViewState {
        var state = OrderDetailViewState(orderID: orderID)
        state.isLoading = true
        return state
    }

    private func makeDetail(status: OrderStatus = .ready) -> OrderDetail {
        OrderDetail(
            orderID: "order-1",
            orderCode: "D123456",
            storeID: "store-1",
            storeName: "새싹 카페",
            storeCategory: "커피",
            storeCloseTime: "21:00",
            storeImagePath: nil,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_710_000_120),
            paidAt: Date(timeIntervalSince1970: 1_710_000_060),
            pickupTime: Date(timeIntervalSince1970: 1_710_000_300),
            totalAmount: 12_200,
            items: [
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
            ],
            timeline: [
                OrderStatusTimelineEntry(id: "pending", status: .pending, completed: true, changedAt: Date(timeIntervalSince1970: 1_710_000_000)),
                OrderStatusTimelineEntry(id: "ready", status: .ready, completed: true, changedAt: Date(timeIntervalSince1970: 1_710_000_300))
            ],
            paymentSummary: OrderPaymentSummary(
                statusText: "paid",
                methodText: "card",
                paidAt: Date(timeIntervalSince1970: 1_710_000_060),
                receiptURL: nil
            ),
            userMemo: "문 앞에서 받아갈게요",
            reviewRating: nil
        )
    }
}

@MainActor
private struct SpyOrderDetailInteractor: OrderDetailInteracting {
    let initialState: OrderDetailViewState
    let fetchResult: Result<OrderDetail, OrderFeatureError>
    var cancelResult: Result<OrderDetail, OrderFeatureError> = .failure(
        .unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
    )

    func loadInitialState() async -> OrderDetailViewState {
        initialState
    }

    func fetchOrderDetail() async throws -> OrderDetail {
        switch fetchResult {
        case .success(let detail):
            return detail
        case .failure(let error):
            throw error
        }
    }

    func makePendingPaymentSession(detail: OrderDetail) async throws -> PendingPaymentSession {
        PendingPaymentSession(
            userID: "user-1",
            orderCode: detail.orderCode,
            orderID: detail.orderID,
            storeID: detail.storeID,
            storeName: detail.storeName,
            menuSummary: detail.paymentRecoveryDisplayName,
            totalPriceAmount: detail.totalAmount,
            createdAt: detail.createdAt,
            state: .recoverablePending,
            impUID: nil,
            lastUpdatedAt: detail.updatedAt
        )
    }

    func savePendingPaymentSession(_ session: PendingPaymentSession) async {}

    func updatePendingPaymentSession(orderCode: String, state: PaymentFlowState, impUID: String?) async {}

    func removePendingPaymentSession(orderCode: String) async {}

    func makePaymentRequest(pendingSession: PendingPaymentSession) async throws -> PaymentGatewayRequest {
        PaymentGatewayRequest(
            orderID: pendingSession.orderID ?? pendingSession.orderCode,
            merchantUID: pendingSession.orderCode,
            amount: pendingSession.totalPriceAmount,
            orderName: pendingSession.menuSummary,
            buyerName: "테스트",
            pg: "html5_inicis",
            pgID: nil,
            payMethod: "card",
            appScheme: "pikko",
            userCode: "imp12345678",
            isTestMode: true
        )
    }

    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt {
        ValidatedPaymentReceipt(
            paymentID: "payment-1",
            orderID: request.orderID,
            orderCode: request.orderCode,
            totalPriceAmount: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt {
        PaymentReceipt(
            impUID: "imp_test",
            merchantUID: orderCode,
            amount: 12_000,
            currency: "KRW",
            status: "paid",
            methodText: "card",
            paidAt: Date(),
            receiptURL: nil
        )
    }

    func refreshOrdersAfterAlreadyValidatedPayment(orderCode: String) async -> Bool {
        true
    }

    func cancelOrder(orderCode: String) async throws -> OrderDetail {
        _ = orderCode
        switch cancelResult {
        case .success(let detail):
            return detail
        case .failure(let error):
            throw error
        }
    }

    func cancelPendingOrderLocally(orderCode: String) async throws -> OrderDetail {
        try await cancelOrder(orderCode: orderCode)
    }
}

@MainActor
private final class SpyOrderDetailRouter: OrderDetailRouting {
    func routeToStoreDetail(storeID: String) {}
    func routeToReviewComposer(context: ReviewComposerContext) {}
    func routeToAuth() {}
    func dismissAuth() {}
    func clearPendingRoute() {}
}

private struct StubAuthorizedFileURLResolver: AuthorizedFileURLResolving {
    func resolveURL(from path: String) throws -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    func resolveOptionalURL(from path: String?) throws -> URL? {
        guard let path else { return nil }
        return try resolveURL(from: path)
    }
}
