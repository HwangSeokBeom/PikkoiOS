import XCTest
@testable import Pikko

@MainActor
final class OrderDetailFeatureTests: XCTestCase {
    func testFetchOrderDetailSuccessReflectsState() async {
        let presenter = OrderDetailPresenter(
            initialOrderID: "order-1",
            interactor: SpyOrderDetailInteractor(
                initialState: makeInitialState(orderID: "order-1"),
                fetchResult: .success(makeDetail())
            ),
            router: SpyOrderDetailRouter(),
            mapper: OrderMapper(fileURLResolver: StubAuthorizedFileURLResolver())
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.hasLoadedContent)
        XCTAssertEqual(presenter.viewState.storeName, "새싹 카페")
        XCTAssertEqual(presenter.viewState.statusTitle, OrderStatus.ready.displayTitle)
        XCTAssertEqual(presenter.viewState.items.count, 2)
        XCTAssertNil(presenter.viewState.emptyState)
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

    private func makeInitialState(orderID: String) -> OrderDetailViewState {
        var state = OrderDetailViewState(orderID: orderID)
        state.isLoading = true
        return state
    }

    private func makeDetail() -> OrderDetail {
        OrderDetail(
            orderID: "order-1",
            orderCode: "D123456",
            storeID: "store-1",
            storeName: "새싹 카페",
            storeCategory: "커피",
            storeCloseTime: "21:00",
            storeImagePath: nil,
            status: .ready,
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
