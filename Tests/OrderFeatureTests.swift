import XCTest
@testable import Pikko

@MainActor
final class OrderFeatureTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await PaymentReceiptCache.shared.clear()
    }

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

    func testPendingPaidOrderShowsCancelButDoesNotCallUnsupportedPutWhenSwaggerHasNoCancelEndpoint() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending)
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [.success(CursorPage(items: [pendingOrder], nextCursor: nil))]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)
        XCTAssertTrue(presenter.viewState.orders.first?.canCancel == true)
        XCTAssertFalse(presenter.viewState.orders.first?.isCancelEnabled ?? true)
        XCTAssertEqual(
            presenter.viewState.orders.first?.cancelDisabledReasonText,
            "결제 취소 API가 필요해요. 매장에 문의해 주세요."
        )

        await presenter.send(.cancelConfirmed("order-1"))

        XCTAssertEqual(presenter.viewState.orders.first?.statusTitle, OrderStatus.pending.displayTitle)
        XCTAssertEqual(
            presenter.viewState.errorMessage,
            "결제 취소 API가 필요해요. 매장에 문의해 주세요."
        )
        XCTAssertTrue(presenter.viewState.orders.first?.canCancel == true)
        XCTAssertTrue(presenter.viewState.cancellingOrderIDs.isEmpty)
    }

    func testPendingOrderWithoutPaymentEvidenceExecutesLocalPendingCancel() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending, paidAt: nil, receiptURL: nil)
        let cancelledDetail = makeDetail(order: pendingOrder, status: .cancelled)
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(CursorPage(items: [pendingOrder], nextCursor: nil)),
                    .success(CursorPage(items: [cancelledDetail.asSummary], nextCursor: nil))
                ],
                localCancelResults: [
                    pendingOrder.orderCode: .success(cancelledDetail)
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        let item = presenter.viewState.orders.first
        XCTAssertTrue(item?.canCancel == true)
        XCTAssertTrue(item?.isCancelEnabled == true)
        XCTAssertEqual(item?.statusTitle, "결제 확인중")

        await presenter.send(.cancelConfirmed("order-1"))

        XCTAssertEqual(presenter.viewState.successMessage, "주문이 취소되었어요.")
        XCTAssertEqual(presenter.viewState.orders.first?.status, .cancelled)
    }

    func testStatusChangeEligibilityRequiresPaidOrderAndOnlyAllowsNextStep() async {
        let paidPendingOrder = makeOrder(id: "order-1", status: .pending, paidAt: Date())
        let unpaidPendingOrder = makeOrder(id: "order-2", status: .pending, paidAt: nil, receiptURL: nil)
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(CursorPage(items: [paidPendingOrder, unpaidPendingOrder], nextCursor: nil))
                ],
                paymentReceiptResults: [
                    paidPendingOrder.orderCode: .success(
                        PaymentReceipt(
                            impUID: "imp_paid",
                            merchantUID: paidPendingOrder.orderCode,
                            amount: 12_000,
                            currency: "KRW",
                            status: "paid",
                            methodText: "card",
                            paidAt: Date(),
                            receiptURL: nil
                        )
                    ),
                    unpaidPendingOrder.orderCode: .success(
                        PaymentReceipt(
                            impUID: "imp_pending",
                            merchantUID: unpaidPendingOrder.orderCode,
                            amount: 12_000,
                            currency: "KRW",
                            status: "ready",
                            methodText: "card",
                            paidAt: nil,
                            receiptURL: nil
                        )
                    )
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        var paidItem = presenter.viewState.orders.first { $0.id == paidPendingOrder.id }
        XCTAssertEqual(paidItem?.paymentVerificationState, .verified)
        XCTAssertEqual(paidItem?.allowedNextStatus, .accepted)
        XCTAssertTrue(paidItem?.isPaymentVerified == true)
        XCTAssertNil(paidItem?.statusChangeMessage)

        await presenter.send(.orderAppeared(paidPendingOrder.id))

        paidItem = presenter.viewState.orders.first { $0.id == paidPendingOrder.id }
        XCTAssertEqual(paidItem?.allowedNextStatus, .accepted)
        XCTAssertTrue(paidItem?.isPaymentVerified == true)
        XCTAssertNil(paidItem?.statusChangeMessage)
        let transitionResolver = OrderStatusTransitionResolver()
        XCTAssertTrue(
            transitionResolver.canTransition(
                currentStatus: .pending,
                nextStatus: .accepted,
                paymentVerificationState: .verified
            )
        )
        XCTAssertFalse(
            transitionResolver.canTransition(
                currentStatus: .pending,
                nextStatus: .completed,
                paymentVerificationState: .verified
            )
        )

        await presenter.send(.orderAppeared(unpaidPendingOrder.id))

        let unpaidItem = presenter.viewState.orders.first { $0.id == unpaidPendingOrder.id }
        XCTAssertNil(unpaidItem?.allowedNextStatus)
        XCTAssertFalse(unpaidItem?.isPaymentVerified ?? true)
        XCTAssertEqual(unpaidItem?.statusTitle, "결제 확인중")
        XCTAssertEqual(unpaidItem?.statusChangeMessage, "결제 정보 확인 후 상태를 변경할 수 있어요.")
    }

    func testPaidOrderWithoutReceiptHintAttemptsPaymentReceiptFetch() async {
        let paidOrderWithoutReceipt = makeOrder(
            id: "order-1",
            status: .pending,
            paidAt: Date(),
            receiptURL: nil
        )
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(CursorPage(items: [paidOrderWithoutReceipt], nextCursor: nil))
                ],
                paymentReceiptResults: [
                    paidOrderWithoutReceipt.orderCode: .success(
                        PaymentReceipt(
                            impUID: "imp_paid",
                            merchantUID: paidOrderWithoutReceipt.orderCode,
                            amount: 12_000,
                            currency: "KRW",
                            status: "paid",
                            methodText: "card",
                            paidAt: Date(),
                            receiptURL: nil
                        )
                    )
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.orderAppeared(paidOrderWithoutReceipt.id))

        let item = presenter.viewState.orders.first { $0.id == paidOrderWithoutReceipt.id }
        XCTAssertEqual(item?.paymentVerificationState, .verified)
        XCTAssertEqual(item?.allowedNextStatus, .accepted)
        XCTAssertTrue(item?.isPaymentVerified == true)
        XCTAssertTrue(item?.isPaymentCompleted == true)
        XCTAssertNil(item?.statusChangeMessage)
    }

    func testPaymentReceiptRefreshUsesPaymentIdentifierBeforeOrderCode() async {
        let order = makeOrder(
            id: "order-1",
            status: .pending,
            paidAt: Date(),
            paymentID: "payment-123"
        )
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(CursorPage(items: [order], nextCursor: nil))
                ],
                paymentReceiptResults: [
                    order.orderCode: .failure(.notFound),
                    "payment-123": .success(
                        PaymentReceipt(
                            impUID: "imp_paid",
                            merchantUID: order.orderCode,
                            amount: 12_000,
                            currency: "KRW",
                            status: "paid",
                            methodText: "card",
                            paidAt: Date(),
                            receiptURL: URL(string: "https://example.com/receipt")
                        )
                    )
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.orderAppeared(order.id))

        let item = presenter.viewState.orders.first { $0.id == order.id }
        XCTAssertEqual(item?.paymentVerificationState, .verified)
        XCTAssertEqual(item?.allowedNextStatus, .accepted)
    }

    func testApprovedOrderOnlyExposesPreparingAndBlocksApprovedReRequest() async {
        let approvedOrder = makeOrder(id: "order-1", status: .accepted, paidAt: Date())
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [
                .success(CursorPage(items: [approvedOrder], nextCursor: nil)),
                .success(CursorPage(items: [approvedOrder], nextCursor: nil))
            ]
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)

        let item = presenter.viewState.orders.first { $0.id == approvedOrder.id }
        XCTAssertEqual(item?.status, .accepted)
        XCTAssertEqual(item?.allowedNextStatus, .preparing)
        XCTAssertNil(item?.statusChangeMessage)

        await presenter.send(.statusChangeConfirmed(orderCode: approvedOrder.orderCode, currentStatus: .accepted, nextStatus: .accepted))
        var statusUpdateRequests = await interactor.statusUpdateRequests()
        XCTAssertTrue(statusUpdateRequests.isEmpty)
        XCTAssertEqual(presenter.viewState.errorMessage, "이미 해당 상태입니다.")

        await presenter.send(.statusChangeConfirmed(orderCode: approvedOrder.orderCode, currentStatus: .accepted, nextStatus: .preparing))
        statusUpdateRequests = await interactor.statusUpdateRequests()
        XCTAssertEqual(statusUpdateRequests, [
            OrderStatusUpdateRequest(orderCode: approvedOrder.orderCode, nextStatus: OrderStatus.preparing.apiValue)
        ])
    }

    func testOrderStatusItemsExposeOnlySequentialNextStatus() async {
        let approvedOrder = makeOrder(id: "order-1", status: .accepted, paidAt: Date())
        let preparingOrder = makeOrder(id: "order-2", status: .preparing, paidAt: Date())
        let readyOrder = makeOrder(id: "order-3", status: .ready, paidAt: Date())
        let completedOrder = makeOrder(id: "order-4", status: .completed, paidAt: Date())
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(CursorPage(items: [approvedOrder, preparingOrder, readyOrder, completedOrder], nextCursor: nil))
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.orders.first { $0.id == approvedOrder.id }?.allowedNextStatus, .preparing)
        XCTAssertEqual(presenter.viewState.orders.first { $0.id == preparingOrder.id }?.allowedNextStatus, .ready)
        XCTAssertEqual(presenter.viewState.orders.first { $0.id == readyOrder.id }?.allowedNextStatus, .completed)
        XCTAssertNil(presenter.viewState.orders.first { $0.id == completedOrder.id }?.allowedNextStatus)
        XCTAssertFalse(presenter.viewState.orders.first { $0.id == completedOrder.id }?.isStatusChangeEnabled ?? true)
    }

    func testInFlightStatusUpdateBlocksDuplicateConfirmationsForSameOrderCode() async {
        let approvedOrder = makeOrder(id: "order-1", status: .accepted, paidAt: Date())
        let preparingOrder = makeOrder(id: "order-1", status: .preparing, paidAt: Date())
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [
                .success(CursorPage(items: [approvedOrder], nextCursor: nil)),
                .success(CursorPage(items: [preparingOrder], nextCursor: nil))
            ],
            statusUpdateDelayNanoseconds: 50_000_000
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)

        async let first: Void = presenter.send(
            .statusChangeConfirmed(orderCode: approvedOrder.orderCode, currentStatus: .accepted, nextStatus: .preparing)
        )
        async let second: Void = presenter.send(
            .statusChangeConfirmed(orderCode: approvedOrder.orderCode, currentStatus: .accepted, nextStatus: .preparing)
        )
        _ = await (first, second)

        let statusUpdateRequests = await interactor.statusUpdateRequests()
        XCTAssertEqual(statusUpdateRequests, [
            OrderStatusUpdateRequest(orderCode: approvedOrder.orderCode, nextStatus: OrderStatus.preparing.apiValue)
        ])
    }

    func testPickedUpReviewEligibilityReflectsReviewID() async {
        let writableOrder = makeOrder(id: "order-1", status: .completed, paidAt: Date())
        let reviewedOrder = makeOrder(id: "order-2", status: .completed, paidAt: Date(), reviewID: "review-2")
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(CursorPage(items: [writableOrder, reviewedOrder], nextCursor: nil))
                ]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)

        let writableItem = presenter.viewState.orders.first { $0.id == writableOrder.id }
        XCTAssertTrue(writableItem?.isReviewWritable == true)
        XCTAssertTrue(writableItem?.canWriteReview == true)
        XCTAssertNil(writableItem?.reviewDisabledReasonText)

        let reviewedItem = presenter.viewState.orders.first { $0.id == reviewedOrder.id }
        XCTAssertFalse(reviewedItem?.isReviewWritable ?? true)
        XCTAssertFalse(reviewedItem?.canWriteReview ?? true)
        XCTAssertEqual(reviewedItem?.reviewDisabledReasonText, "이미 이 주문에 대한 리뷰를 작성했어요.")
    }

    func testUnknownCurrentStatusBlocksPutAndRefreshesOrders() async {
        let unknownOrder = makeOrder(id: "order-1", status: .unknown("unknown"), paidAt: Date())
        let refreshedOrder = makeOrder(id: "order-1", status: .accepted, paidAt: Date())
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [
                .success(CursorPage(items: [unknownOrder], nextCursor: nil)),
                .success(CursorPage(items: [refreshedOrder], nextCursor: nil))
            ]
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)
        await presenter.send(.statusChangeConfirmed(orderCode: unknownOrder.orderCode, currentStatus: .unknown("unknown"), nextStatus: .accepted))

        let statusUpdateRequests = await interactor.statusUpdateRequests()
        let fetchRequests = await interactor.fetchRequests()
        XCTAssertTrue(statusUpdateRequests.isEmpty)
        XCTAssertEqual(fetchRequests.count, 2)
        XCTAssertEqual(presenter.viewState.errorMessage, "주문 상태를 확인할 수 없어 최신 주문 정보를 다시 불러왔습니다.")
        XCTAssertEqual(presenter.viewState.orders.first?.status, .accepted)
    }

    func testStatusUpdateFailureShowsServerMessageAndKeepsServerStatus() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending, paidAt: Date())
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [
                .success(CursorPage(items: [pendingOrder], nextCursor: nil))
            ],
            statusUpdateResults: [
                pendingOrder.orderCode: .failure(.unavailable(message: "요청한 주문 상태로 변경할 수 없습니다."))
            ],
            paymentReceiptResults: [
                pendingOrder.orderCode: .success(
                    PaymentReceipt(
                        impUID: "imp_paid",
                        merchantUID: pendingOrder.orderCode,
                        amount: 12_000,
                        currency: "KRW",
                        status: "paid",
                        methodText: "card",
                        paidAt: Date(),
                        receiptURL: nil
                    )
                )
            ]
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)
        await presenter.send(.orderAppeared(pendingOrder.id))
        await presenter.send(.statusChangeConfirmed(orderCode: pendingOrder.orderCode, currentStatus: .pending, nextStatus: .accepted))

        let statusUpdateRequests = await interactor.statusUpdateRequests()
        XCTAssertEqual(statusUpdateRequests, [
            OrderStatusUpdateRequest(orderCode: pendingOrder.orderCode, nextStatus: OrderStatus.accepted.apiValue)
        ])
        XCTAssertEqual(presenter.viewState.errorMessage, "요청한 주문 상태로 변경할 수 없습니다.")
        XCTAssertEqual(presenter.viewState.orders.first?.status, .pending)
    }

    func testSuccessfulApprovalUpdatesLocalStatusAndBlocksDuplicateApprovedWhenRefreshIsStale() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending, paidAt: Date())
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [
                .success(CursorPage(items: [pendingOrder], nextCursor: nil)),
                .success(CursorPage(items: [pendingOrder], nextCursor: nil))
            ],
            paymentReceiptResults: [
                pendingOrder.orderCode: .success(
                    PaymentReceipt(
                        impUID: "imp_paid",
                        merchantUID: pendingOrder.orderCode,
                        amount: 12_000,
                        currency: "KRW",
                        status: "paid",
                        methodText: "card",
                        paidAt: Date(),
                        receiptURL: nil
                    )
                )
            ]
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)
        await presenter.send(.orderAppeared(pendingOrder.id))
        await presenter.send(.statusChangeConfirmed(orderCode: pendingOrder.orderCode, currentStatus: .pending, nextStatus: .accepted))

        XCTAssertEqual(presenter.viewState.orders.first?.status, .accepted)
        XCTAssertEqual(presenter.viewState.orders.first?.allowedNextStatus, .preparing)

        await presenter.send(.statusChangeConfirmed(orderCode: pendingOrder.orderCode, currentStatus: .accepted, nextStatus: .accepted))

        let statusUpdateRequests = await interactor.statusUpdateRequests()
        XCTAssertEqual(statusUpdateRequests, [
            OrderStatusUpdateRequest(orderCode: pendingOrder.orderCode, nextStatus: OrderStatus.accepted.apiValue)
        ])
        XCTAssertEqual(presenter.viewState.errorMessage, "이미 해당 상태입니다.")
    }

    func testPendingOrderCannotSkipDirectlyToPreparing() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending, paidAt: Date())
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [.success(CursorPage(items: [pendingOrder], nextCursor: nil))],
            paymentReceiptResults: [
                pendingOrder.orderCode: .success(
                    PaymentReceipt(
                        impUID: "imp_paid",
                        merchantUID: pendingOrder.orderCode,
                        amount: 12_000,
                        currency: "KRW",
                        status: "paid",
                        methodText: "card",
                        paidAt: Date(),
                        receiptURL: nil
                    )
                )
            ]
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)
        await presenter.send(.orderAppeared(pendingOrder.id))
        await presenter.send(.statusChangeConfirmed(orderCode: pendingOrder.orderCode, currentStatus: .pending, nextStatus: .preparing))

        let statusUpdateRequests = await interactor.statusUpdateRequests()
        XCTAssertTrue(statusUpdateRequests.isEmpty)
        XCTAssertEqual(presenter.viewState.errorMessage, "현재 주문 상태에서 다음 단계만 변경할 수 있어요.")
    }

    func testPendingOrderWithoutPaymentEvidenceCannotApprove() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending, paidAt: nil, receiptURL: nil)
        let interactor = SpyOrderInteractor(
            initialState: makeInitialState(),
            fetchResults: [.success(CursorPage(items: [pendingOrder], nextCursor: nil))],
            paymentReceiptResults: [
                pendingOrder.orderCode: .failure(.notFound)
            ]
        )
        let presenter = OrderPresenter(interactor: interactor, router: SpyOrderRouter())

        await presenter.send(.onAppear)
        await presenter.send(.orderAppeared(pendingOrder.id))
        await presenter.send(.statusChangeConfirmed(orderCode: pendingOrder.orderCode, currentStatus: .pending, nextStatus: .accepted))

        let statusUpdateRequests = await interactor.statusUpdateRequests()
        XCTAssertTrue(statusUpdateRequests.isEmpty)
        XCTAssertNil(presenter.viewState.orders.first?.allowedNextStatus)
        XCTAssertEqual(presenter.viewState.errorMessage, "결제 완료 확인 후 상태를 변경할 수 있어요.")
    }

    func testPendingPaidOrderCancelFailureStaysInActiveFilterWhenNoServerCancelAPI() async {
        let pendingOrder = makeOrder(id: "order-1", status: .pending)
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [.success(CursorPage(items: [pendingOrder], nextCursor: nil))]
            ),
            router: SpyOrderRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.filterTapped(.active))
        await presenter.send(.cancelConfirmed("order-1"))

        XCTAssertEqual(presenter.viewState.orders.first?.id, "order-1")
        XCTAssertNil(presenter.viewState.emptyState)
        XCTAssertEqual(
            presenter.viewState.errorMessage,
            "결제 취소 API가 필요해요. 매장에 문의해 주세요."
        )
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

    func testPaymentValidationSuccessNotificationRefreshesLoadedOrderList() async {
        let router = SpyOrderRouter()
        let presenter = OrderPresenter(
            interactor: SpyOrderInteractor(
                initialState: makeInitialState(),
                fetchResults: [
                    .success(CursorPage(items: [], nextCursor: nil)),
                    .success(CursorPage(items: [makeOrder(id: "order-validated", status: .pending)], nextCursor: nil))
                ]
            ),
            router: router
        )

        await presenter.send(.onAppear)
        NotificationCenter.default.post(
            name: .pikkoOrdersShouldRefresh,
            object: nil,
            userInfo: [
                OrderRefreshNotificationUserInfoKey.event: OrderRefreshNotification(
                    orderID: "order-validated",
                    orderCode: "D-order-validated",
                    message: "주문이 접수되었습니다. 목록 반영까지 잠시 걸릴 수 있습니다."
                )
            ]
        )
        let refreshExpectation = expectation(description: "orders refresh notification handled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            refreshExpectation.fulfill()
        }
        await fulfillment(of: [refreshExpectation], timeout: 1.0)

        XCTAssertEqual(presenter.viewState.orders.map(\.id), ["order-validated"])
        XCTAssertEqual(presenter.viewState.successMessage, "주문 내역을 최신 상태로 새로고침했어요.")
        XCTAssertEqual(router.routedOrderIDs, ["order-validated"])
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

    func testRepositoryDoesNotUseStatusUpdateAPIForCancellationWithoutSwaggerCancelEndpoint() async throws {
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

        do {
            _ = try await repository.cancelOrder(orderCode: "D123456")
            XCTFail("Expected unsupported cancellation error")
        } catch let error as NetworkError {
            XCTAssertEqual(
                error.localizedDescription,
                "현재 서버에서 주문 취소를 지원하지 않아요. 매장에 문의해 주세요."
            )
        }
        XCTAssertTrue(remoteDataSource.updateStatusRequests.isEmpty)
    }

    func testRepositoryDoesNotPersistCancelledOverrideWhenCancellationUnsupported() async throws {
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

        _ = try? await repository.cancelOrder(orderCode: "D123456")
        let page = try await repository.fetchOrders(cursor: nil, filter: nil)

        XCTAssertEqual(page.items.first?.status, .preparing)
        XCTAssertTrue(remoteDataSource.updateStatusRequests.isEmpty)
    }

    func testLocalCancellationStorePersistsAndRemovesStaleCancellationWhenServerProgresses() async {
        let suiteName = #function + UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = LocalOrderCancellationStore(store: UserDefaultsStore(userDefaults: userDefaults))
        let userID = "user-1"
        let pendingOrder = makeOrder(id: "order-1", status: .pending, paidAt: nil, receiptURL: nil)

        await store.save(order: pendingOrder, userID: userID)
        let reloadedStore = LocalOrderCancellationStore(store: UserDefaultsStore(userDefaults: userDefaults))
        let locallyCancelled = await reloadedStore.apply(to: pendingOrder, userID: userID)

        XCTAssertEqual(locallyCancelled.status, .cancelled)

        let progressedOrder = makeOrder(id: "order-1", status: .preparing, paidAt: nil, receiptURL: nil)
        let serverPreferred = await reloadedStore.apply(to: progressedOrder, userID: userID)
        let pendingAfterConflict = await reloadedStore.apply(to: pendingOrder, userID: userID)

        XCTAssertEqual(serverPreferred.status, .preparing)
        XCTAssertEqual(pendingAfterConflict.status, .pending)
    }

    func testHiddenOrderHistoryStoreFiltersCompletedOrdersButKeepsActiveOrdersVisible() async {
        let suiteName = #function + UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = HiddenOrderHistoryStore(store: UserDefaultsStore(userDefaults: userDefaults))
        let userID = "user-1"
        let completedOrder = makeOrder(id: "completed", status: .completed)
        let activeOrder = makeOrder(id: "active", status: .preparing)

        await store.hide(order: completedOrder, userID: userID)
        await store.hide(order: activeOrder, userID: userID)
        let filtered = await store.apply(to: [completedOrder, activeOrder], userID: userID)

        XCTAssertEqual(filtered.map { $0.orderCode }, [activeOrder.orderCode])
    }

    func testHiddenOrderHistoryStoreUndoRestoresHiddenCompletedOrder() async {
        let suiteName = #function + UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = HiddenOrderHistoryStore(store: UserDefaultsStore(userDefaults: userDefaults))
        let userID = "user-1"
        let completedOrder = makeOrder(id: "completed", status: .completed)

        await store.hide(order: completedOrder, userID: userID)
        let hiddenBeforeUndo = await store.isHidden(orderCode: completedOrder.orderCode, userID: userID)
        XCTAssertTrue(hiddenBeforeUndo)

        await store.unhide(orderCode: completedOrder.orderCode, userID: userID)

        let hiddenAfterUndo = await store.isHidden(orderCode: completedOrder.orderCode, userID: userID)
        XCTAssertFalse(hiddenAfterUndo)
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
        itemSummaries: [OrderItemSummary]? = nil,
        paidAt: Date? = nil,
        paymentID: String? = nil,
        receiptURL: URL? = URL(string: "https://example.com/receipt"),
        reviewID: String? = nil,
        reviewRating: Decimal? = nil
    ) -> OrderSummary {
        OrderSummary(
            id: id,
            orderCode: "D-\(id)",
            storeID: "store-\(id)",
            storeName: storeName,
            storeImagePath: nil,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            paidAt: paidAt,
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
            reviewID: reviewID,
            reviewRating: reviewRating,
            paymentID: paymentID,
            receiptURL: receiptURL,
            receiptExists: receiptURL != nil
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
            localSnapshotStore: localSnapshotStore,
            statusOverrideStore: makeStatusOverrideStore()
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

    private func makeStatusOverrideStore() -> OrderStatusOverrideStore {
        let suiteName = #function + UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return OrderStatusOverrideStore(
            store: UserDefaultsStore(userDefaults: userDefaults),
            storageKey: "test.order.statusOverrides",
            ttl: 1_800
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
        let json = """
        {
          "imp_uid": "imp_test",
          "merchant_uid": "\(orderCode)",
          "amount": 12000,
          "currency": "KRW",
          "status": "paid",
          "pay_method": "card",
          "paidAt": "2024-03-09T16:00:00Z"
        }
        """.data(using: .utf8)!
        return try NetworkCoding.makeJSONDecoder().decode(PaymentResponseDTO.self, from: json)
    }

    func validatePayment(_ request: PaymentValidationRequestDTO) async throws -> ReceiptOrderResponseDTO {
        _ = request
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

private extension OrderDetail {
    var asSummary: OrderSummary {
        OrderSummary(
            id: orderID,
            orderCode: orderCode,
            storeID: storeID,
            storeName: storeName,
            storeImagePath: storeImagePath,
            status: status,
            createdAt: createdAt,
            paidAt: paidAt,
            totalAmount: totalAmount,
            itemSummaries: items,
            pickupTime: pickupTime,
            reviewID: reviewID,
            reviewRating: reviewRating,
            paymentStatus: paymentSummary?.statusText,
            receiptURL: paymentSummary?.receiptURL,
            receiptExists: paymentSummary?.receiptURL != nil
        )
    }
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
    var localCancelResults: [String: Result<OrderDetail, OrderFeatureError>] = [:]
    var statusUpdateResults: [String: Result<Void, OrderFeatureError>] = [:]
    var paymentReceiptResults: [String: Result<PaymentReceipt, OrderFeatureError>] = [:]
    var statusUpdateDelayNanoseconds: UInt64 = 0

    private let recorder = OrderFetchRecorder()
    private let statusUpdateRecorder = OrderStatusUpdateRecorder()

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

    func statusUpdateRequests() async -> [OrderStatusUpdateRequest] {
        await statusUpdateRecorder.requests
    }

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt {
        if let result = paymentReceiptResults[orderCode] {
            switch result {
            case .success(let receipt):
                return receipt
            case .failure(let error):
                throw error
            }
        }

        return PaymentReceipt(
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

    func cancelPendingOrderLocally(orderCode: String) async throws -> OrderDetail {
        guard let result = localCancelResults[orderCode] else {
            return OrderDetail(
                orderID: orderCode,
                orderCode: orderCode,
                storeID: "",
                storeName: "주문",
                storeCategory: nil,
                storeCloseTime: nil,
                storeImagePath: nil,
                status: .cancelled,
                createdAt: Date(timeIntervalSince1970: 1_710_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_710_000_120),
                paidAt: nil,
                pickupTime: nil,
                totalAmount: 0,
                items: [],
                timeline: [
                    OrderStatusTimelineEntry(id: "cancelled", status: .cancelled, completed: true, changedAt: Date())
                ],
                paymentSummary: nil,
                userMemo: nil,
                reviewRating: nil
            )
        }

        switch result {
        case .success(let detail):
            return detail
        case .failure(let error):
            throw error
        }
    }

    func hideOrderFromHistory(orderCode: String) async throws {}

    func unhideOrderFromHistory(orderCode: String) async {}

    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws {
        await statusUpdateRecorder.append(orderCode: orderCode, nextStatus: status.apiValue)
        if statusUpdateDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: statusUpdateDelayNanoseconds)
        }
        guard let result = statusUpdateResults[orderCode] else {
            return
        }

        switch result {
        case .success:
            return
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

private actor OrderStatusUpdateRecorder {
    private(set) var requests: [OrderStatusUpdateRequest] = []

    func append(orderCode: String, nextStatus: String) {
        requests.append(OrderStatusUpdateRequest(orderCode: orderCode, nextStatus: nextStatus))
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
