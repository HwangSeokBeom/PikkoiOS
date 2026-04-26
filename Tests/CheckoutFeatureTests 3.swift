import XCTest
@testable import Pikko

@MainActor
final class CheckoutFeatureTests: XCTestCase {
    func testCheckoutInteractorBuildsOrderSubmissionFromDraft() async throws {
        let createdOrder = CreatedOrder(
            id: "order-1",
            orderCode: "D123456",
            totalPriceAmount: 12_200,
            createdAt: Date(),
            updatedAt: Date()
        )
        let repository = SpyOrderRepository(createdOrder: createdOrder)
        let interactor = CheckoutInteractor(
            draft: makeDraft(),
            orderRepository: repository
        )

        let order = try await interactor.submitOrder()
        let receivedSubmission = await repository.takeReceivedSubmission()
        let submission = try XCTUnwrap(receivedSubmission)

        XCTAssertEqual(order.orderCode, "D123456")
        XCTAssertEqual(submission.storeID, "store-1")
        XCTAssertEqual(submission.items.count, 2)
        XCTAssertEqual(submission.items.first?.menuID, "menu-1")
        XCTAssertEqual(submission.items.first?.quantity, 2)
        XCTAssertEqual(submission.totalPriceAmount, 12_200)
        XCTAssertEqual(submission.paymentMethod, .card)
        XCTAssertEqual(submission.address?.label, "수령지 미설정")
        XCTAssertNil(submission.coupon)
    }

    func testCheckoutPresenterStoresCreatedOrderCodeOnSuccess() async {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())
        cartStore.setQuantity(
            2,
            menuID: "menu-1",
            menuName: "카페라떼",
            unitPrice: 4_500,
            imagePath: nil,
            storeID: "store-1",
            storeName: "새싹 카페"
        )
        let router = CheckoutRouter()
        let presenter = CheckoutPresenter(
            interactor: StubCheckoutInteractor(
                initialState: CheckoutViewState(
                    storeName: "새싹 카페",
                    items: [
                        CheckoutItemViewState(
                            id: "menu-1",
                            name: "카페라떼",
                            optionSummaryText: "기본 옵션",
                            quantity: 1,
                            unitPriceText: "4,500원",
                            subtotalText: "4,500원"
                        )
                    ],
                    totalPriceText: "4,500원",
                    isPrimaryEnabled: true,
                    isEmpty: false
                ),
                submitResult: .success(
                    CreatedOrder(
                        id: "order-1",
                        orderCode: "D123456",
                        totalPriceAmount: 4_500,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                )
            ),
            router: router,
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)

        XCTAssertEqual(presenter.viewState.createdOrderID, "order-1")
        XCTAssertEqual(presenter.viewState.createdOrderCode, "D123456")
        XCTAssertEqual(presenter.viewState.primaryActionTitle, "주문 생성 완료")
        XCTAssertFalse(presenter.viewState.isPrimaryEnabled)
        XCTAssertEqual(presenter.viewState.totalPriceText, "4,500원")
        XCTAssertNotNil(presenter.viewState.successMessage)
        XCTAssertEqual(cartStore.summary.itemCount, 0)

        await presenter.send(.orderHistoryTapped)

        XCTAssertEqual(router.pendingRoute, .orderHistory(orderID: "order-1"))
    }

    func testCheckoutPresenterMapsAuthenticationFailure() async {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())
        let presenter = CheckoutPresenter(
            interactor: StubCheckoutInteractor(
                initialState: CheckoutViewState(
                    storeName: "새싹 카페",
                    items: [
                        CheckoutItemViewState(
                            id: "menu-1",
                            name: "카페라떼",
                            optionSummaryText: "기본 옵션",
                            quantity: 1,
                            unitPriceText: "4,500원",
                            subtotalText: "4,500원"
                        )
                    ],
                    totalPriceText: "4,500원",
                    isPrimaryEnabled: true,
                    isEmpty: false
                ),
                submitResult: .failure(.authenticationRequired)
            ),
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)

        XCTAssertEqual(presenter.viewState.errorMessage, "로그인 후 주문을 생성할 수 있어요.")
        XCTAssertEqual(presenter.viewState.primaryActionTitle, "주문 다시 생성하기")
        XCTAssertTrue(presenter.viewState.isPrimaryEnabled)
        XCTAssertNil(presenter.viewState.createdOrderCode)
    }

    private func makeDraft() -> CheckoutDraft {
        CheckoutDraft(
            storeID: "store-1",
            storeName: "새싹 카페",
            items: [
                CheckoutDraftLineItem(
                    menuID: "menu-1",
                    menuName: "카페라떼",
                    imagePath: nil,
                    optionSummaryText: nil,
                    unitPriceAmount: 4_500,
                    unitPriceText: "4,500원",
                    quantity: 2,
                    subtotalAmount: 9_000,
                    subtotalText: "9,000원"
                ),
                CheckoutDraftLineItem(
                    menuID: "menu-2",
                    menuName: "휘낭시에",
                    imagePath: nil,
                    optionSummaryText: nil,
                    unitPriceAmount: 3_200,
                    unitPriceText: "3,200원",
                    quantity: 1,
                    subtotalAmount: 3_200,
                    subtotalText: "3,200원"
                )
            ],
            itemCount: 3,
            subtotalAmount: 12_200,
            subtotalText: "12,200원"
        )
    }
}

private actor SpyOrderRepository: OrderRepository {
    private(set) var receivedSubmission: CheckoutOrderSubmission?
    private let createdOrder: CreatedOrder

    init(createdOrder: CreatedOrder) {
        self.createdOrder = createdOrder
    }

    func createOrder(_ submission: CheckoutOrderSubmission) async throws -> CreatedOrder {
        receivedSubmission = submission
        return createdOrder
    }

    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func fetchOrderDetail(orderID: String) async throws -> OrderDetail {
        throw NetworkError.notFound(message: "주문 정보를 찾을 수 없어요.")
    }

    func validatePayment(impUID: String) async throws -> ValidatedPaymentReceipt {
        _ = impUID
        return ValidatedPaymentReceipt(
            paymentID: nil,
            orderID: nil,
            orderCode: nil,
            totalPriceAmount: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    func validatePrice(_ request: CheckoutPriceValidationRequest) async throws -> CheckoutPriceValidationResult {
        _ = request
        return .valid
    }

    func takeReceivedSubmission() -> CheckoutOrderSubmission? {
        receivedSubmission
    }
}

@MainActor
private struct StubCheckoutInteractor: CheckoutInteracting {
    let initialState: CheckoutViewState
    let submitResult: Result<CreatedOrder, CheckoutFeatureError>

    func loadInitialState() async -> CheckoutViewState {
        initialState
    }

    func submitOrder() async throws -> CreatedOrder {
        switch submitResult {
        case .success(let order):
            return order
        case .failure(let error):
            throw error
        }
    }
}
