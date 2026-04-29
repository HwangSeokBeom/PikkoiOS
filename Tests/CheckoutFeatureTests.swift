import XCTest
@testable import Pikko

@MainActor
final class CheckoutFeatureTests: XCTestCase {
    func testCheckoutMapperBuildsPriceValidationDTOFromRequest() {
        let request = CheckoutPriceValidationRequest(
            storeID: "store-1",
            items: [
                CheckoutPriceValidationLineItem(
                    menuID: "menu-1",
                    quantity: 2,
                    optionSummaryText: "샷 추가",
                    clientKnownUnitPriceAmount: 4_500,
                    clientKnownLinePriceAmount: 9_000
                )
            ],
            totalPriceAmount: 9_000,
            couponID: "coupon-1"
        )

        let dto = CheckoutMapper().mapValidationRequest(request)

        XCTAssertEqual(dto.storeID, "store-1")
        XCTAssertEqual(dto.totalPrice, 9_000)
        XCTAssertEqual(dto.couponID, "coupon-1")
        XCTAssertEqual(dto.orderMenuList.count, 1)
        XCTAssertEqual(dto.orderMenuList.first?.menuID, "menu-1")
        XCTAssertEqual(dto.orderMenuList.first?.clientKnownLinePrice, 9_000)
    }

    func testCheckoutInteractorBuildsOrderSubmissionFromDraft() async throws {
        let createdOrder = CreatedOrder(
            id: "order-1",
            orderCode: "D123456",
            totalPriceAmount: 12_200,
            createdAt: Date(),
            updatedAt: Date(),
            paymentBridgePayload: nil
        )
        let repository = SpyOrderRepository(
            validationResult: .valid,
            createdOrder: createdOrder
        )
        let interactor = CheckoutInteractor(
            draft: makeDraft(),
            orderRepository: repository,
            appConfiguration: makePaymentConfiguration()
        )

        let order = try await interactor.createOrder(
            input: CheckoutSubmissionInput(
                address: .placeholder,
                paymentMethod: .card,
                coupon: nil,
                pickupMemo: "문 앞에서 받아갈게요"
            )
        )
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
        XCTAssertEqual(submission.pickupMemo, "문 앞에서 받아갈게요")
    }

    func testCheckoutInteractorBuildsValidationRequestFromDraft() async throws {
        let repository = SpyOrderRepository(validationResult: .valid)
        let interactor = CheckoutInteractor(
            draft: makeDraft(),
            orderRepository: repository,
            appConfiguration: makePaymentConfiguration()
        )

        _ = try await interactor.validatePrice(
            input: CheckoutSubmissionInput(
                address: .placeholder,
                paymentMethod: .card,
                coupon: nil,
                pickupMemo: ""
            )
        )

        let receivedRequest = await repository.takeReceivedValidationRequest()
        let request = try XCTUnwrap(receivedRequest)
        XCTAssertEqual(request.storeID, "store-1")
        XCTAssertEqual(request.items.count, 2)
        XCTAssertEqual(request.totalPriceAmount, 12_200)
        XCTAssertEqual(request.items.first?.clientKnownLinePriceAmount, 9_000)
    }

    func testCheckoutInteractorBuildsPortOneRequestFromOrderCode() async throws {
        let interactor = CheckoutInteractor(
            draft: makeDraft(),
            orderRepository: SpyOrderRepository(validationResult: .valid),
            appConfiguration: makePaymentConfiguration()
        )

        let paymentRequest = try await interactor.makePaymentRequest(
            createdOrder: CreatedOrder(
                id: "order-1",
                orderCode: "ORDER-001",
                totalPriceAmount: 12_200,
                createdAt: Date(),
                updatedAt: Date(),
                paymentBridgePayload: nil
            )
        )

        XCTAssertEqual(paymentRequest.merchantUID, "ORDER-001")
        XCTAssertEqual(paymentRequest.amount, 12_200)
        XCTAssertEqual(paymentRequest.orderName, "카페라떼 외 1개")
        XCTAssertEqual(paymentRequest.pg, "html5_inicis")
        XCTAssertEqual(paymentRequest.pgID, "INIpayTest")
        XCTAssertEqual(paymentRequest.appScheme, "pikko")
    }

    func testCheckoutPresenterCreatesOrderAfterValidationSuccess() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "D123456",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            )
        )
        let router = CheckoutRouter()
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: router,
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.pickupMemoChanged("얼음 적게 부탁드려요"))
        await presenter.send(.primaryButtonTapped)

        let recordedEvents = await interactor.recordedEvents()
        XCTAssertEqual(recordedEvents, [.loadInitialState, .validatePrice, .createOrder, .makePaymentRequest])
        XCTAssertEqual(presenter.viewState.createdOrderID, "order-1")
        XCTAssertEqual(presenter.viewState.createdOrderCode, "D123456")
        XCTAssertEqual(presenter.viewState.paymentStage, .presentingPayment)
        XCTAssertEqual(presenter.viewState.paymentBridgeContext?.paymentRequest.merchantUID, "D123456")
        XCTAssertEqual(cartStore.summary.itemCount, 2)
        XCTAssertNil(router.pendingRoute)
    }

    func testCheckoutPresenterDoesNotCreateOrderWhenValidationFails() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(
                CheckoutPriceValidationResult(
                    validatedTotalPriceAmount: 4_700,
                    issues: [
                        CheckoutPriceValidationIssue(
                            id: "menu-1",
                            menuID: "menu-1",
                            kind: .priceChanged,
                            message: "가격이 변경되었어요."
                        )
                    ],
                    message: "주문 정보를 다시 확인해 주세요."
                )
            ),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "D123456",
                    totalPriceAmount: 4_700,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)

        let recordedEvents = await interactor.recordedEvents()
        XCTAssertEqual(recordedEvents, [.loadInitialState, .validatePrice])
        XCTAssertEqual(presenter.viewState.validationIssues.count, 1)
        XCTAssertEqual(presenter.viewState.items.first?.validationMessage, "가격이 변경되었어요.")
        XCTAssertNil(presenter.viewState.createdOrderID)
        XCTAssertEqual(cartStore.summary.itemCount, 2)
    }

    func testCheckoutPresenterReflectsOrderCreationFailure() async {
        let cartStore = makeFilledCartStore()
        let router = CheckoutRouter()
        let presenter = CheckoutPresenter(
            interactor: SpyCheckoutInteractor(
                initialState: makeLoadedViewState(),
                validationResult: .success(.valid),
                createResult: .failure(.authenticationRequired)
            ),
            router: router,
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)

        XCTAssertEqual(presenter.viewState.errorMessage, "로그인 후 주문을 생성할 수 있어요.")
        XCTAssertTrue(router.isAuthPresented)
        XCTAssertNil(presenter.viewState.createdOrderCode)
        XCTAssertEqual(cartStore.summary.itemCount, 2)
    }

    func testCheckoutPresenterIgnoresDuplicatePrimaryTapWhileSubmitting() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "D123456",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            ),
            validationDelayNanos: 100_000_000
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)

        async let first: Void = presenter.send(.primaryButtonTapped)
        async let second: Void = presenter.send(.primaryButtonTapped)
        _ = await (first, second)

        let recordedEvents = await interactor.recordedEvents()
        XCTAssertEqual(recordedEvents, [.loadInitialState, .validatePrice, .createOrder, .makePaymentRequest])
    }

    func testCheckoutPresenterValidatesPaymentAfterBridgeSuccess() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            ),
            validatePaymentResult: .success(
                ValidatedPaymentReceipt(
                    paymentID: "payment-1",
                    orderID: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)

        XCTAssertEqual(presenter.viewState.paymentBridgeContext?.orderCode, "ORDER-001")
        XCTAssertFalse(presenter.viewState.showsCompletionView)

        await presenter.send(.paymentBridgeResult(.succeeded(impUID: "imp_123", merchantUID: "ORDER-001")))

        let recordedEvents = await interactor.recordedEvents()
        let validatedRequest = await interactor.lastValidatedRequest()
        XCTAssertEqual(recordedEvents, [.loadInitialState, .validatePrice, .createOrder, .makePaymentRequest, .validatePayment])
        XCTAssertEqual(validatedRequest?.impUID, "imp_123")
        XCTAssertEqual(validatedRequest?.merchantUID, "ORDER-001")
        XCTAssertEqual(presenter.viewState.completionState, .paymentValidated)
        XCTAssertEqual(presenter.viewState.paymentStage, .paymentCompleted)
        XCTAssertTrue(presenter.viewState.showsCompletionView)
        XCTAssertNil(presenter.viewState.paymentBridgeContext)
        XCTAssertEqual(cartStore.summary.itemCount, 0)
    }

    func testCheckoutPresenterShowsValidationFailedStateWhenPaymentValidationFails() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            ),
            validatePaymentResult: .failure(
                .unavailable(message: "PG 승인 확인이 지연되고 있어요.")
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)
        await presenter.send(.paymentBridgeResult(.succeeded(impUID: "imp_delayed", merchantUID: "ORDER-001")))

        XCTAssertEqual(presenter.viewState.completionState, .none)
        XCTAssertEqual(presenter.viewState.paymentStage, .paymentValidationFailed)
        XCTAssertFalse(presenter.viewState.showsCompletionView)
        XCTAssertEqual(presenter.viewState.primaryActionTitle, "결제 확인 재시도")
        XCTAssertEqual(
            presenter.viewState.errorMessage,
            "결제 확인에 실패했습니다. 결제가 실제로 완료되었을 수 있으니 잠시 후 주문 내역을 확인하거나 고객센터에 문의해주세요."
        )
        XCTAssertEqual(cartStore.summary.itemCount, 2)
    }

    func testCheckoutPresenterRetriesValidationWithoutCreatingNewOrderAfterValidationFailure() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            ),
            validatePaymentResult: .failure(
                .unavailable(message: "PG 승인 확인이 지연되고 있어요.")
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)
        await presenter.send(.paymentBridgeResult(.succeeded(impUID: "imp_delayed", merchantUID: "ORDER-001")))
        await presenter.send(.primaryButtonTapped)

        let recordedEvents = await interactor.recordedEvents()
        let validatedRequests = await interactor.validatedRequests()
        XCTAssertEqual(
            recordedEvents,
            [.loadInitialState, .validatePrice, .createOrder, .makePaymentRequest, .validatePayment, .validatePayment]
        )
        XCTAssertEqual(validatedRequests.count, 2)
        XCTAssertEqual(validatedRequests.first?.impUID, "imp_delayed")
        XCTAssertEqual(validatedRequests.last?.orderCode, "ORDER-001")
        XCTAssertEqual(cartStore.summary.itemCount, 2)
    }

    func testCheckoutPresenterKeepsCartAndSkipsValidationWhenImpUIDIsMissing() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)
        await presenter.send(.paymentBridgeResult(.missingImpUID))

        let recordedEvents = await interactor.recordedEvents()
        XCTAssertEqual(recordedEvents, [.loadInitialState, .validatePrice, .createOrder, .makePaymentRequest])
        XCTAssertEqual(presenter.viewState.paymentStage, .paymentFailed)
        XCTAssertEqual(cartStore.summary.itemCount, 2)
    }

    func testCheckoutPresenterKeepsCartAndSkipsValidationWhenPaymentFails() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)
        await presenter.send(.paymentBridgeResult(.failed(message: "결제를 완료하지 못했어요.")))

        let recordedEvents = await interactor.recordedEvents()
        XCTAssertEqual(recordedEvents, [.loadInitialState, .validatePrice, .createOrder, .makePaymentRequest])
        XCTAssertEqual(presenter.viewState.paymentStage, .paymentFailed)
        XCTAssertEqual(cartStore.summary.itemCount, 2)
    }

    func testCheckoutPresenterKeepsCartAndSkipsValidationAfterPaymentCancellation() async {
        let cartStore = makeFilledCartStore()
        let router = CheckoutRouter()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: router,
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)
        await presenter.send(.paymentBridgeResult(.cancelled))

        XCTAssertEqual(presenter.viewState.primaryActionTitle, "결제 다시 시도하기")
        XCTAssertEqual(presenter.viewState.paymentStage, .paymentCanceled)
        XCTAssertFalse(presenter.viewState.canRouteToOrderHistoryFromPrimary)
        XCTAssertEqual(cartStore.summary.itemCount, 2)

        await presenter.send(.primaryButtonTapped)

        XCTAssertNil(router.pendingRoute)
    }

    func testCheckoutPresenterIgnoresPrimaryTapWhilePaymentIsPresented() async {
        let cartStore = makeFilledCartStore()
        let interactor = SpyCheckoutInteractor(
            initialState: makeLoadedViewState(),
            validationResult: .success(.valid),
            createResult: .success(
                CreatedOrder(
                    id: "order-1",
                    orderCode: "ORDER-001",
                    totalPriceAmount: 4_500,
                    createdAt: Date(),
                    updatedAt: Date(),
                    paymentBridgePayload: nil
                )
            )
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: CheckoutRouter(),
            cartStore: cartStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.primaryButtonTapped)
        await presenter.send(.primaryButtonTapped)

        let recordedEvents = await interactor.recordedEvents()
        XCTAssertEqual(recordedEvents, [.loadInitialState, .validatePrice, .createOrder, .makePaymentRequest])
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

    private func makeLoadedViewState() -> CheckoutViewState {
        CheckoutViewState(
            storeName: "새싹 카페",
            summaryText: "요약",
            addressSummaryText: CheckoutAddress.placeholder.summaryText,
            paymentMethodSummaryText: CheckoutPaymentMethod.card.summaryText,
            couponSummaryText: "적용 쿠폰 없음",
            pickupMemo: "",
            items: [
                CheckoutItemViewState(
                    id: "menu-1",
                    name: "카페라떼",
                    optionSummaryText: "기본 옵션",
                    quantity: 1,
                    unitPriceText: "4,500원",
                    subtotalText: "4,500원",
                    validationMessage: nil
                )
            ],
            validationIssues: [],
            isValidatingPrice: false,
            isSubmittingOrder: false,
            totalPriceText: "4,500원",
            primaryActionTitle: "주문 생성하기",
            isPrimaryEnabled: true,
            isPrimaryLoading: false,
            createdOrderID: nil,
            createdOrderCode: nil,
            errorMessage: nil,
            successMessage: nil,
            isEmpty: false
        )
    }

    private func makePaymentBridgePayload() -> CheckoutPaymentBridgePayload {
        CheckoutPaymentBridgePayload(
            paymentURL: URL(string: "https://payments.example.com/start"),
            redirectURL: URL(string: "pikko://payments/callback"),
            paymentToken: "token-1"
        )
    }

    private func makeFilledCartStore() -> CartStore {
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
        return cartStore
    }

    private func makePaymentConfiguration(environment: AppEnvironment = .development) -> AppConfiguration {
        AppConfiguration(
            environment: environment,
            baseURL: URL(string: "http://pickup.sesac.kr:42678"),
            seSACKey: "test-sesac-key",
            portOneUserCode: "imp_test",
            portOnePg: "html5_inicis",
            portOnePgID: "INIpayTest",
            portOnePayMethod: "card",
            portOneAppScheme: "pikko",
            paymentTestMode: true
        )
    }
}

private actor SpyOrderRepository: OrderRepository {
    private(set) var receivedValidationRequest: CheckoutPriceValidationRequest?
    private(set) var receivedSubmission: CheckoutOrderSubmission?
    private let validationResult: CheckoutPriceValidationResult
    private let createdOrder: CreatedOrder?

    init(
        validationResult: CheckoutPriceValidationResult,
        createdOrder: CreatedOrder? = nil
    ) {
        self.validationResult = validationResult
        self.createdOrder = createdOrder
    }

    func validatePrice(_ request: CheckoutPriceValidationRequest) async throws -> CheckoutPriceValidationResult {
        receivedValidationRequest = request
        return validationResult
    }

    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func fetchOrderDetail(orderID: String) async throws -> OrderDetail {
        throw NetworkError.notFound(message: "주문 정보를 찾을 수 없어요.")
    }

    func cancelOrder(orderCode: String) async throws -> OrderDetail {
        _ = orderCode
        throw NetworkError.invalidRequest
    }

    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt {
        _ = request
        return ValidatedPaymentReceipt(
            paymentID: nil,
            orderID: nil,
            orderCode: nil,
            totalPriceAmount: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    func createOrder(_ submission: CheckoutOrderSubmission) async throws -> CreatedOrder {
        receivedSubmission = submission
        guard let createdOrder else {
            throw CheckoutFeatureError.unavailable(message: "생성된 주문 fixture가 없어요.")
        }
        return createdOrder
    }

    func takeReceivedValidationRequest() -> CheckoutPriceValidationRequest? {
        receivedValidationRequest
    }

    func takeReceivedSubmission() -> CheckoutOrderSubmission? {
        receivedSubmission
    }
}

@MainActor
private struct SpyCheckoutInteractor: CheckoutInteracting {
    enum Event: Equatable {
        case loadInitialState
        case validatePrice
        case createOrder
        case makePaymentRequest
        case validatePayment
    }

    let initialState: CheckoutViewState
    let validationResult: Result<CheckoutPriceValidationResult, CheckoutFeatureError>
    let createResult: Result<CreatedOrder, CheckoutFeatureError>
    let validatePaymentResult: Result<ValidatedPaymentReceipt, CheckoutFeatureError>
    var validationDelayNanos: UInt64 = 0

    private let recorder = EventRecorder()
    private let validationRequestRecorder = PaymentValidationRequestRecorder()

    init(
        initialState: CheckoutViewState,
        validationResult: Result<CheckoutPriceValidationResult, CheckoutFeatureError>,
        createResult: Result<CreatedOrder, CheckoutFeatureError>,
        validatePaymentResult: Result<ValidatedPaymentReceipt, CheckoutFeatureError> = .success(
            ValidatedPaymentReceipt(
                paymentID: nil,
                orderID: nil,
                orderCode: nil,
                totalPriceAmount: nil,
                createdAt: nil,
                updatedAt: nil
            )
        ),
        validationDelayNanos: UInt64 = 0
    ) {
        self.initialState = initialState
        self.validationResult = validationResult
        self.createResult = createResult
        self.validatePaymentResult = validatePaymentResult
        self.validationDelayNanos = validationDelayNanos
    }

    func loadInitialState() async -> CheckoutViewState {
        await recorder.append(.loadInitialState)
        return initialState
    }

    func validatePrice(input: CheckoutSubmissionInput) async throws -> CheckoutPriceValidationResult {
        await recorder.append(.validatePrice)
        if validationDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: validationDelayNanos)
        }
        switch validationResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    func createOrder(input: CheckoutSubmissionInput) async throws -> CreatedOrder {
        await recorder.append(.createOrder)
        switch createResult {
        case .success(let order):
            return order
        case .failure(let error):
            throw error
        }
    }

    func makePaymentRequest(createdOrder: CreatedOrder) async throws -> PaymentGatewayRequest {
        await recorder.append(.makePaymentRequest)
        return PaymentGatewayRequest(
            orderID: createdOrder.id,
            merchantUID: createdOrder.orderCode,
            amount: createdOrder.totalPriceAmount,
            orderName: "카페라떼",
            buyerName: "테스트 사용자",
            pg: "html5_inicis",
            pgID: "INIpayTest",
            payMethod: "card",
            appScheme: "pikko",
            userCode: "imp_test",
            isTestMode: true
        )
    }

    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt {
        await recorder.append(.validatePayment)
        await validationRequestRecorder.set(request)
        switch validatePaymentResult {
        case .success(let receipt):
            return receipt
        case .failure(let error):
            throw error
        }
    }

    func recordedEvents() async -> [Event] {
        await recorder.events
    }

    func lastValidatedRequest() async -> PaymentValidationRequest? {
        await validationRequestRecorder.value
    }

    func validatedRequests() async -> [PaymentValidationRequest] {
        await validationRequestRecorder.values
    }
}

private actor EventRecorder {
    private(set) var events: [SpyCheckoutInteractor.Event] = []

    func append(_ event: SpyCheckoutInteractor.Event) {
        events.append(event)
    }
}

    private actor PaymentValidationRequestRecorder {
    private(set) var value: PaymentValidationRequest?
    private(set) var values: [PaymentValidationRequest] = []

    func set(_ value: PaymentValidationRequest) {
        self.value = value
        values.append(value)
    }
}
