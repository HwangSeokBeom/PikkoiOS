import Combine
import Foundation

@MainActor
final class OrderPresenter: ObservableObject {
    @Published private(set) var viewState = OrderViewState()

    private let interactor: OrderInteracting
    private let router: OrderRouting
    private let paymentReceiptCache: PaymentReceiptCache
    private let transitionResolver = OrderStatusTransitionResolver()
    private let cancelPolicyResolver = OrderCancelPolicyResolver()
    private let reviewEligibilityResolver = OrderReviewEligibilityResolver()
    private let currencyFormatter = CurrencyFormatter()
    private let dateParser = DateParser()

    private var hasLoaded = false
    private var isRequestInFlight = false
    private var hasAutoNavigatedHighlightedOrder = false
    private var allOrders: [OrderSummary] = []
    private var paymentVerificationStates: [String: PaymentVerificationState] = [:]
    private var paymentReceiptRequestsInFlight = Set<String>()
    private var inFlightOrderStatusUpdateOrderCodes = Set<String>()
    private var lastSuccessfulOrderStatusByOrderCode: [String: OrderStatus] = [:]
    private var lastLoggedOrderViewStateByOrderCode: [String: OrderViewStateLogSnapshot] = [:]
    private var lastLoggedReviewEligibilityByOrderCode: [String: ReviewEligibilityLogSnapshot] = [:]
    private var lastLoggedOrderMappingByOrderCode: [String: OrderMappingLogSnapshot] = [:]
    private var lastLoggedPaymentAutoFetchDecisionByOrderCode: [String: PaymentAutoFetchLogSnapshot] = [:]
    private var lastLoggedReviewEligibilitySummary: ReviewEligibilitySummaryLogSnapshot?
    private var noPaymentEvidenceCache: [String: Date] = [:]
    private var currentReviewEligibilitySummary = ReviewEligibilitySummary()
    private var orderListRequestID = 0
    private var cancellables = Set<AnyCancellable>()

    init(
        interactor: OrderInteracting,
        router: OrderRouting,
        paymentReceiptCache: PaymentReceiptCache = .shared
    ) {
        self.interactor = interactor
        self.router = router
        self.paymentReceiptCache = paymentReceiptCache
        bindOrderStatusChanges()
        bindOrderRefreshRequests()
    }

    convenience init(interactor: OrderInteracting, router: OrderRouting) {
        self.init(interactor: interactor, router: router, paymentReceiptCache: .shared)
    }

    func send(_ action: OrderAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
            guard viewState.isInitialLoading else { return }
            _ = await loadOrders(mode: .initial)

        case .refreshRequested:
            _ = await loadOrders(mode: .refresh)

        case .retryTapped:
            _ = await loadOrders(mode: viewState.orders.isEmpty ? .initial : .refresh)

        case .filterTapped(let filter):
            guard viewState.selectedFilter != filter else { return }
            viewState.selectedFilter = filter
            applyOrders(resetErrorMessage: false, reason: "filter")
            await attemptAutoNavigationIfNeeded()

        case .orderTapped(let orderID):
            router.routeToOrderDetail(orderID: orderID)

        case .cancelConfirmed(let orderID):
            await cancelOrder(orderID: orderID)

        case .statusSelected(let orderCode, let currentStatus, let nextStatus):
            Logger.shared.debug(
                "[OrderStatus] select orderCode=\(orderCode) current=\(currentStatus.apiValue) currentTitle=\(currentStatus.displayTitle) next=\(nextStatus.apiValue) nextTitle=\(nextStatus.displayTitle)"
            )
            handleStatusSelection(orderCode: orderCode, currentStatus: currentStatus, nextStatus: nextStatus)

        case .statusChangeConfirmed(let orderCode, let currentStatus, let nextStatus):
            await updateOrderStatus(orderCode: orderCode, selectedCurrentStatus: currentStatus, nextStatus: nextStatus)

        case .orderAppeared(let orderID):
            if let order = allOrders.first(where: { $0.id == orderID }) {
                await refreshPaymentReceiptIfNeeded(orderCode: order.orderCode, force: false)
            }
            guard orderID == viewState.orders.last?.id,
                  viewState.canLoadMore,
                  !viewState.isLoadingMore,
                  !isRequestInFlight else { return }
            _ = await loadOrders(mode: .loadMore)

        case .paymentReceiptRefreshRequested(let orderCode, let force):
            await refreshPaymentReceiptIfNeeded(orderCode: orderCode, force: force)

        case .loginRequiredTapped:
            router.routeToAuth()

        case .exploreStoresTapped:
            router.routeToExploreHome()
        }
    }

    @discardableResult
    private func loadOrders(mode: LoadingMode) async -> Bool {
        guard !isRequestInFlight else { return false }
        isRequestInFlight = true
        orderListRequestID += 1
        let requestID = orderListRequestID
        setLoadingFlags(for: mode, isLoading: true)
        if mode != .loadMore {
            viewState.errorMessage = nil
            viewState.successMessage = nil
        }

        do {
            let page = try await interactor.fetchOrders(
                cursor: mode == .loadMore ? viewState.nextCursor : nil,
                filter: viewState.selectedFilter
            )
            await merge(page: page, mode: mode, requestID: requestID)
            applyOrders(resetErrorMessage: true, reason: mode.logReason)
            await attemptAutoNavigationIfNeeded()
        } catch {
            apply(error: error, mode: mode)
            setLoadingFlags(for: mode, isLoading: false)
            isRequestInFlight = false
            return false
        }

        setLoadingFlags(for: mode, isLoading: false)
        isRequestInFlight = false
        return true
    }

    private func merge(page: CursorPage<OrderSummary>, mode: LoadingMode, requestID: Int) async {
        switch mode {
        case .initial, .refresh:
            allOrders = deduplicated(page.items)
        case .loadMore:
            let existingIDs = Set(allOrders.map(\.id))
            let appended = page.items.filter { !existingIDs.contains($0.id) }
            allOrders.append(contentsOf: appended)
        }

        viewState.nextCursor = normalize(cursor: page.nextCursor)
        viewState.canLoadMore = viewState.nextCursor != nil
        viewState.emptyState = nil
        viewState.requiresAuthentication = false
        await preparePaymentVerificationStates(for: allOrders, requestID: requestID, source: "ordersDTO")
    }

    private func applyOrders(resetErrorMessage: Bool, reason: String) {
        let filteredOrders = allOrders.filter { viewState.selectedFilter.includes(status: $0.status) }
        currentReviewEligibilitySummary = ReviewEligibilitySummary()
        let mappedOrders = filteredOrders.map(mapListItem)
        logOrderViewStateDiff(mappedOrders, reason: reason)
        logReviewEligibilitySummary(total: mappedOrders.count)
        viewState.orders = mappedOrders

        if resetErrorMessage {
            viewState.errorMessage = nil
        }

        if filteredOrders.isEmpty {
            viewState.emptyState = makeEmptyState()
        } else {
            viewState.emptyState = nil
        }
    }

    private func apply(error: Error, mode: LoadingMode) {
        let featureError = (error as? OrderFeatureError) ?? .unavailable(message: "주문 내역을 불러오지 못했어요.")

        if case .authenticationRequired = featureError {
            allOrders = []
            viewState.orders = []
            viewState.requiresAuthentication = true
            viewState.emptyState = OrderEmptyState(
                title: "로그인이 필요해요",
                message: featureError.userMessage,
                actionTitle: "로그인하러 가기",
                requiresAuthentication: true
            )
            viewState.errorMessage = nil
            viewState.canLoadMore = false
            viewState.nextCursor = nil
            return
        }

        if allOrders.isEmpty || mode != .loadMore {
            viewState.emptyState = OrderEmptyState(
                title: mode == .refresh ? "주문 내역을 새로고침하지 못했어요" : "주문 내역을 불러오지 못했어요",
                message: featureError.userMessage,
                actionTitle: "다시 시도",
                requiresAuthentication: false
            )
        } else {
            viewState.errorMessage = featureError.userMessage
        }
        viewState.canLoadMore = false
        viewState.nextCursor = nil
    }

    private func attemptAutoNavigationIfNeeded() async {
        guard let highlightedOrderID = viewState.highlightedOrderID,
              !hasAutoNavigatedHighlightedOrder,
              viewState.orders.contains(where: { $0.id == highlightedOrderID }) else {
            return
        }

        hasAutoNavigatedHighlightedOrder = true
        router.routeToOrderDetail(orderID: highlightedOrderID)
    }

    private func setLoadingFlags(for mode: LoadingMode, isLoading: Bool) {
        switch mode {
        case .initial:
            viewState.isInitialLoading = isLoading
        case .refresh:
            viewState.isRefreshing = isLoading
        case .loadMore:
            viewState.isLoadingMore = isLoading
        }
    }

    private func mapListItem(_ order: OrderSummary) -> OrderListItemViewState {
        let primaryMenuName = order.itemSummaries.first?.menuName ?? "메뉴 정보 준비 중"
        let totalItemCount = order.itemSummaries.reduce(0) { $0 + $1.quantity }
        let additionalCount = max(totalItemCount - 1, 0)
        let primaryItemText = additionalCount > 0 ? "\(primaryMenuName) 외 \(additionalCount)개" : primaryMenuName
        let createdAtText = dateParser.string(from: order.createdAt, format: "M월 d일 a h:mm")
        let pickupTimeText = order.pickupTime.map { "픽업 예상 \($0.formatted(date: .omitted, time: .shortened))" }
        let currentStatus = effectiveStatus(for: order)
        let paymentVerificationState = paymentVerificationStates[order.orderCode] ?? .unchecked
        let isPaymentVerified = paymentVerificationState.isVerified
        let transitionDecision = transitionDecision(
            orderCode: order.orderCode,
            currentStatus: currentStatus,
            paymentVerificationState: paymentVerificationState
        )
        let allowedNextStatus = transitionDecision.allowedNextStatus
        let cancelPolicy = cancelPolicyResolver.policy(
            rawStatus: order.status,
            mappedStatus: currentStatus,
            paid: isPaymentVerified,
            paymentLookupKey: order.paymentLookupKey,
            paymentID: order.paymentID,
            merchantUID: order.merchantUID,
            impUID: order.impUID
        )
        let canShowCancelButton = cancelPolicy.canShowCancelButton
        let isCancelEnabled = cancelPolicy.canExecuteCancel
        let reviewEligibility = reviewEligibilityResolver.decision(
            storeID: order.storeID,
            status: currentStatus,
            paymentVerificationState: paymentVerificationState,
            reviewID: order.reviewID
        )
        currentReviewEligibilitySummary.record(decision: reviewEligibility)
        logReviewEligibility(
            order: order,
            status: currentStatus,
            paymentVerificationState: paymentVerificationState,
            decision: reviewEligibility
        )
        let displayStatusTitle = statusTitle(
            for: currentStatus,
            paymentVerificationState: paymentVerificationState
        )
        logOrderState(
            order: order,
            mappedStatus: currentStatus,
            paymentVerificationState: paymentVerificationState,
            canCancel: canShowCancelButton,
            canChangeStatus: transitionDecision.isStatusChangeEnabled,
            reviewEligibilityReason: reviewEligibility.reason
        )
        logOrderCancelPolicy(
            order: order,
            mappedStatus: currentStatus,
            paymentVerificationState: paymentVerificationState,
            policy: cancelPolicy
        )

        return OrderListItemViewState(
            id: order.id,
            orderCode: order.orderCode,
            storeName: order.storeName,
            storeImagePath: order.storeImagePath,
            status: currentStatus,
            statusTitle: displayStatusTitle,
            currentStatus: currentStatus,
            currentStatusTitle: displayStatusTitle,
            statusSteps: makeProgressSteps(for: currentStatus),
            primaryItemText: primaryItemText,
            itemRows: order.itemSummaries.map(makeMenuItemRow),
            itemCountText: "\(totalItemCount)EA",
            createdAtText: createdAtText,
            pickupTimeText: pickupTimeText,
            totalPriceText: currencyFormatter.string(from: order.totalAmount),
            reviewRatingText: order.reviewRating.map { rating in
                let value = NSDecimalNumber(decimal: rating).doubleValue
                return String(format: "%.1f", value)
            },
            isHighlighted: order.id == viewState.highlightedOrderID,
            canCancel: canShowCancelButton,
            isCancelling: viewState.cancellingOrderIDs.contains(order.id),
            isStatusUpdating: inFlightOrderStatusUpdateOrderCodes.contains(order.orderCode),
            paymentVerificationState: paymentVerificationState,
            isPaymentVerified: isPaymentVerified,
            isPaymentCompleted: order.isPaymentCompleted,
            allowedNextStatus: allowedNextStatus,
            allowedNextStatusTitle: allowedNextStatus?.displayTitle,
            isStatusChangeEnabled: transitionDecision.isStatusChangeEnabled,
            statusChangeMessage: transitionDecision.disabledReasonText,
            disabledReasonText: transitionDecision.disabledReasonText,
            cancelDisabledReasonText: cancelPolicy.userMessage,
            canRefreshPaymentReceipt: canRefreshPaymentReceipt(
                for: order,
                paymentVerificationState: paymentVerificationState
            ),
            isCancelEnabled: isCancelEnabled,
            isReviewWritable: reviewEligibility.isWritable,
            reviewDisabledReasonText: reviewEligibility.disabledReasonText,
            isPastOrder: currentStatus.isTerminal,
            canWriteReview: reviewEligibility.isWritable
        )
    }

    private func makeMenuItemRow(_ item: OrderItemSummary) -> OrderMenuItemViewState {
        OrderMenuItemViewState(
            id: item.id,
            name: item.menuName,
            quantityText: "\(item.quantity)EA",
            priceText: item.unitPriceAmount.map { currencyFormatter.string(from: $0) } ?? "-",
            imagePath: item.imagePath
        )
    }

    private func statusTitle(
        for status: OrderStatus,
        paymentVerificationState: PaymentVerificationState
    ) -> String {
        guard !paymentVerificationState.isVerified,
              !status.isTerminal else {
            return status.displayTitle
        }
        return "결제 확인중"
    }

    private func canRefreshPaymentReceipt(
        for order: OrderSummary,
        paymentVerificationState: PaymentVerificationState
    ) -> Bool {
        guard paymentVerificationState.shouldShowRefreshAction else {
            return false
        }
        return order.paymentEvidenceSource != "none"
    }

    private func logOrderState(
        order: OrderSummary,
        mappedStatus: OrderStatus,
        paymentVerificationState: PaymentVerificationState,
        canCancel: Bool,
        canChangeStatus: Bool,
        reviewEligibilityReason: String
    ) {
        Logger.shared.debug(
            "[OrderState] orderCode=\(order.orderCode) rawOrderStatus=\(order.status.apiValue) mappedOrderStatus=\(mappedStatus.apiValue) paid=\(paymentVerificationState.isVerified) paidAtExists=\(order.paidAt != nil) receiptExists=\(order.receiptExists) receiptUrlExists=\(order.receiptURL != nil) paymentEvidenceSource=\(order.paymentEvidenceSource) canCancel=\(canCancel) canChangeStatus=\(canChangeStatus) reviewEligibilityReason=\(reviewEligibilityReason)"
        )
    }

    private func logOrderCancelPolicy(
        order: OrderSummary,
        mappedStatus: OrderStatus,
        paymentVerificationState: PaymentVerificationState,
        policy: OrderCancelPolicy
    ) {
        Logger.shared.debug(
            "[OrderCancelPolicy] orderCode=\(order.orderCode) rawStatus=\(order.status.apiValue) mappedStatus=\(mappedStatus.apiValue) paid=\(paymentVerificationState.isVerified) evidence=\(order.paymentEvidenceSource) paymentId=\(maskedPaymentLookupValue(order.paymentID)) impUid=\(maskedPaymentLookupValue(order.impUID)) merchantUid=\(maskedPaymentLookupValue(order.merchantUID)) canShowCancelButton=\(policy.canShowCancelButton) canExecuteCancel=\(policy.canExecuteCancel) reason=\(policy.reason.rawValue) cancelEndpointAvailable=\(policy.cancelEndpointAvailable) hasPaymentIdentifier=\(policy.hasPaymentIdentifier) debugReason=\(policy.debugReason)"
        )
        Logger.shared.debug(
            "[OrderCancelRender] orderCode=\(order.orderCode) rawStatus=\(order.status.apiValue) paid=\(paymentVerificationState.isVerified) canShowCancelButton=\(policy.canShowCancelButton) strategy=\(policy.strategy.rawValue)"
        )
    }

    private func logOrderViewStateDiff(_ orders: [OrderListItemViewState], reason: String) {
        let nextSnapshots = Dictionary(
            uniqueKeysWithValues: orders.map { order in
                (
                    order.orderCode,
                    OrderViewStateLogSnapshot(
                        status: order.status,
                        allowedNextStatus: order.allowedNextStatus,
                        isStatusChangeEnabled: order.isStatusChangeEnabled,
                        isReviewWritable: order.isReviewWritable
                    )
                )
            }
        )
        let changedOrderCodes = orders.compactMap { order -> String? in
            guard let previous = lastLoggedOrderViewStateByOrderCode[order.orderCode] else {
                return nil
            }
            return previous != nextSnapshots[order.orderCode] ? order.orderCode : nil
        }

        if !changedOrderCodes.isEmpty {
            Logger.shared.debug(
                "[OrderViewState] diff reason=\(reason) changedOrderCodes=\(changedOrderCodes) total=\(orders.count)"
            )
        }

        lastLoggedOrderViewStateByOrderCode = nextSnapshots
    }

    private func logReviewEligibility(
        order: OrderSummary,
        status: OrderStatus,
        paymentVerificationState: PaymentVerificationState,
        decision: OrderReviewEligibilityDecision
    ) {
        let snapshot = ReviewEligibilityLogSnapshot(
            storeID: order.storeID,
            status: status,
            paymentVerificationState: paymentVerificationState,
            alreadyReviewed: decision.alreadyReviewed,
            matchedReviewID: decision.matchedReviewID,
            isWritable: decision.isWritable,
            reason: decision.reason
        )
        let previous = lastLoggedReviewEligibilityByOrderCode[order.orderCode]
        guard previous != snapshot else {
            Logger.shared.debugVerbose(
                "[ReviewEligibility] orderCode=\(order.orderCode) storeId=\(order.storeID.isEmpty ? "nil" : order.storeID) status=\(status.apiValue) paymentState=\(paymentVerificationState.logValue) alreadyReviewed=\(decision.alreadyReviewed) matchedReviewId=\(decision.matchedReviewID ?? "nil") isWritable=\(decision.isWritable) reason=\(decision.reason)"
            )
            return
        }

        lastLoggedReviewEligibilityByOrderCode[order.orderCode] = snapshot
        guard let previous else {
            Logger.shared.debugVerbose(
                "[ReviewEligibility] orderCode=\(order.orderCode) storeId=\(order.storeID.isEmpty ? "nil" : order.storeID) status=\(status.apiValue) paymentState=\(paymentVerificationState.logValue) alreadyReviewed=\(decision.alreadyReviewed) matchedReviewId=\(decision.matchedReviewID ?? "nil") isWritable=\(decision.isWritable) reason=\(decision.reason)"
            )
            return
        }
        Logger.shared.debug(
            "[ReviewEligibility] changed orderCode=\(order.orderCode) previousWritable=\(previous.isWritable) isWritable=\(decision.isWritable) reason=\(decision.reason) matchedReviewId=\(decision.matchedReviewID ?? "nil")"
        )
    }

    private func logReviewEligibilitySummary(total: Int) {
        let snapshot = ReviewEligibilitySummaryLogSnapshot(
            total: total,
            writable: currentReviewEligibilitySummary.writable,
            alreadyReviewed: currentReviewEligibilitySummary.alreadyReviewed,
            notPickedUp: currentReviewEligibilitySummary.notPickedUp
        )
        guard lastLoggedReviewEligibilitySummary != snapshot else {
            Logger.shared.debugVerbose(
                "[ReviewEligibility] summary total=\(snapshot.total) writable=\(snapshot.writable) alreadyReviewed=\(snapshot.alreadyReviewed) notPickedUp=\(snapshot.notPickedUp)"
            )
            return
        }
        lastLoggedReviewEligibilitySummary = snapshot
        Logger.shared.debug(
            "[ReviewEligibility] summary total=\(snapshot.total) writable=\(snapshot.writable) alreadyReviewed=\(snapshot.alreadyReviewed) notPickedUp=\(snapshot.notPickedUp)"
        )
    }

    private func transitionDecision(
        orderCode: String,
        currentStatus: OrderStatus,
        paymentVerificationState: PaymentVerificationState
    ) -> OrderStatusTransitionDecision {
        _ = orderCode
        return transitionResolver.decision(
            currentStatus: currentStatus,
            paymentVerificationState: paymentVerificationState
        )
    }

    private func makeProgressSteps(for status: OrderStatus) -> [OrderProgressStepViewState] {
        let orderedStatuses: [OrderStatus] = [.pending, .accepted, .preparing, .ready, .completed]

        if status.isExceptionTerminal || status.progressStepIndex == nil {
            return [
                OrderProgressStepViewState(
                    id: status.displayTitle,
                    title: status.displayTitle,
                    timeText: status.isExceptionTerminal ? "주문이 종료되었어요" : nil,
                    state: status.isExceptionTerminal ? .exception : .current
                )
            ]
        }

        let currentIndex = status.progressStepIndex ?? 0
        return orderedStatuses.enumerated().map { index, stepStatus in
            let state: OrderProgressStepViewState.State
            if index < currentIndex {
                state = .completed
            } else if index == currentIndex {
                state = .current
            } else {
                state = .pending
            }

            return OrderProgressStepViewState(
                id: stepStatus.displayTitle,
                title: stepStatus.displayTitle,
                timeText: nil,
                state: state
            )
        }
    }

    private func cancelOrder(orderID: String) async {
        guard let order = allOrders.first(where: { $0.id == orderID }) else { return }
        let paymentVerificationState = paymentVerificationStates[order.orderCode] ?? .unchecked
        let effectiveStatus = effectiveStatus(for: order)
        let cancelPolicy = cancelPolicyResolver.policy(
            rawStatus: order.status,
            mappedStatus: effectiveStatus,
            paid: paymentVerificationState.isVerified,
            paymentLookupKey: order.paymentLookupKey,
            paymentID: order.paymentID,
            merchantUID: order.merchantUID,
            impUID: order.impUID
        )
        Logger.shared.debug(
            "[OrderCancel] tapped orderCode=\(order.orderCode) strategy=\(cancelPolicy.strategy.rawValue)"
        )
        guard cancelPolicy.canExecuteCancel else {
            Logger.shared.debug(
                "[OrderCancel] request method=none path=none orderCode=\(order.orderCode) strategy=\(cancelPolicy.strategy.rawValue)"
            )
            Logger.shared.warning(
                "[OrderCancel] failed orderCode=\(order.orderCode) statusCode=none serverMessage=\(cancelPolicy.userMessage ?? "unsupported") strategy=\(cancelPolicy.strategy.rawValue)"
            )
            viewState.errorMessage = cancelPolicy.userMessage ?? "현재 주문은 앱에서 취소할 수 없어요."
            applyOrders(resetErrorMessage: false, reason: "cancelBlocked")
            return
        }
        guard !viewState.cancellingOrderIDs.contains(orderID) else { return }

        viewState.cancellingOrderIDs.insert(orderID)
        viewState.errorMessage = nil
        viewState.successMessage = nil
        applyOrders(resetErrorMessage: false, reason: "cancelStart")

        do {
            let detail: OrderDetail
            switch cancelPolicy.strategy {
            case .serverOrderCancel:
                Logger.shared.debug(
                    "[OrderCancel] request method=none path=none orderCode=\(order.orderCode) strategy=\(cancelPolicy.strategy.rawValue)"
                )
                detail = try await interactor.cancelOrder(orderCode: order.orderCode)
            case .serverPaymentCancel:
                Logger.shared.debug(
                    "[OrderCancel] request method=none path=none orderCode=\(order.orderCode) strategy=\(cancelPolicy.strategy.rawValue)"
                )
                detail = try await interactor.cancelOrder(orderCode: order.orderCode)
            case .localPendingCancel:
                detail = try await interactor.cancelPendingOrderLocally(orderCode: order.orderCode)
            case .unsupported:
                throw OrderFeatureError.unavailable(message: cancelPolicy.userMessage ?? "현재 주문은 앱에서 취소할 수 없어요.")
            }
            if detail.orderID != detail.orderCode || detail.storeID.isEmpty == false {
                upsert(detail: detail)
            }
            Logger.shared.debug("[OrderCancel] success orderCode=\(order.orderCode)")
            _ = await loadOrders(mode: .refresh)
            viewState.successMessage = cancelPolicy.strategy == .serverPaymentCancel
                ? "주문과 결제가 취소되었어요."
                : "주문이 취소되었어요."
        } catch {
            let featureError = (error as? OrderFeatureError)
                ?? .unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
            Logger.shared.warning(
                "[OrderCancel] failed orderCode=\(order.orderCode) statusCode=unknown serverMessage=\(featureError.userMessage) strategy=\(cancelPolicy.strategy.rawValue)"
            )
            _ = await loadOrders(mode: .refresh)
            viewState.errorMessage = cancelFailureUserMessage(from: featureError, fallback: cancelPolicy.userMessage)
        }

        viewState.cancellingOrderIDs.remove(orderID)
        applyOrders(resetErrorMessage: false, reason: "cancelEnd")
    }

    private func cancelFailureUserMessage(from error: OrderFeatureError, fallback: String?) -> String {
        if error.userMessage.contains("결제가 완료된 주문만") {
            return "아직 결제 확인이 완료되지 않아 취소할 수 없어요."
        }
        if error.userMessage.contains("transport") {
            return "네트워크 연결을 확인한 뒤 다시 시도해주세요."
        }
        return fallback ?? "주문 취소에 실패했어요. 잠시 후 다시 시도해주세요."
    }

    private func handleStatusSelection(orderCode: String, currentStatus: OrderStatus, nextStatus: OrderStatus) {
        guard let order = allOrders.first(where: { $0.orderCode == orderCode }) else {
            Logger.shared.warning(
                "[OrderStatus] requestSkipped reason=staleCell orderCode=\(orderCode) currentStatus=\(currentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "주문 상태를 확인할 수 없어 최신 주문 정보를 다시 불러왔습니다."
            return
        }
        let effectiveCurrentStatus = effectiveStatus(for: order)
        guard effectiveCurrentStatus == currentStatus else {
            Logger.shared.warning(
                "[OrderStatus] requestSkipped reason=staleCell orderCode=\(orderCode) selectedCurrentStatus=\(currentStatus.apiValue) serverCurrentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "주문 상태가 변경되어 최신 상태를 기준으로 다시 확인해 주세요."
            applyOrders(resetErrorMessage: false, reason: "staleStatusSelection")
            return
        }
        if inFlightOrderStatusUpdateOrderCodes.contains(orderCode) {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=inFlight orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            return
        }
        if effectiveCurrentStatus == nextStatus {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=sameStatus orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "이미 해당 상태입니다."
            return
        }
        let currentPaymentVerificationState = paymentVerificationStates[orderCode] ?? .unchecked
        let allowedNextStatus = transitionDecision(
            orderCode: orderCode,
            currentStatus: effectiveCurrentStatus,
            paymentVerificationState: currentPaymentVerificationState
        ).allowedNextStatus
        let isValidSelection = allowedNextStatus == nextStatus
        Logger.shared.debug(
            "[OrderStatus] selectionChanged orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) selectedNextStatus=\(nextStatus.apiValue) allowedNextStatus=\(allowedNextStatus?.apiValue ?? "nil") isValidSelection=\(isValidSelection)"
        )
        if !currentPaymentVerificationState.isVerified {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=notPaymentVerified orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "결제 완료 확인 후 상태를 변경할 수 있어요."
            return
        }
        guard allowedNextStatus == nextStatus else {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=invalidTransition orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue) allowedNextStatus=\(allowedNextStatus?.apiValue ?? "nil")"
            )
            viewState.errorMessage = "다음 단계로만 변경할 수 있습니다."
            return
        }
        viewState.errorMessage = nil
    }

    private func updateOrderStatus(orderCode: String, selectedCurrentStatus: OrderStatus?, nextStatus: OrderStatus) async {
        guard let order = allOrders.first(where: { $0.orderCode == orderCode }) else {
            Logger.shared.warning(
                "[OrderStatus] requestSkipped reason=staleCell orderCode=\(orderCode) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            _ = await loadOrders(mode: .refresh)
            viewState.errorMessage = "주문 상태를 확인할 수 없어 최신 주문 정보를 다시 불러왔습니다."
            return
        }
        let effectiveCurrentStatus = effectiveStatus(for: order)
        if let selectedCurrentStatus,
           selectedCurrentStatus != effectiveCurrentStatus {
            Logger.shared.warning(
                "[OrderStatus] requestSkipped reason=staleCell orderCode=\(orderCode) selectedCurrentStatus=\(selectedCurrentStatus.apiValue) serverCurrentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            applyOrders(resetErrorMessage: false, reason: "staleStatusConfirm")
            viewState.errorMessage = "주문 상태가 변경되어 최신 상태를 기준으로 다시 확인해 주세요."
            return
        }
        guard !inFlightOrderStatusUpdateOrderCodes.contains(orderCode) else {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=inFlight orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            return
        }
        guard effectiveCurrentStatus != nextStatus else {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=sameStatus orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "이미 해당 상태입니다."
            return
        }
        guard effectiveCurrentStatus.canEvaluateStatusTransition else {
            Logger.shared.warning(
                "[OrderStatus] requestSkipped reason=invalidTransition orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            _ = await loadOrders(mode: .refresh)
            viewState.errorMessage = "주문 상태를 확인할 수 없어 최신 주문 정보를 다시 불러왔습니다."
            return
        }

        let currentPaymentVerificationState = paymentVerificationStates[orderCode] ?? .unchecked
        let allowedNextStatus = transitionDecision(
            orderCode: orderCode,
            currentStatus: effectiveCurrentStatus,
            paymentVerificationState: currentPaymentVerificationState
        ).allowedNextStatus
        Logger.shared.debug(
            "[OrderStatus] eligibility orderCode=\(orderCode) rawPaymentVerificationState=\(order.paymentVerificationState ?? "unchecked") mergedPaymentVerificationState=\(currentPaymentVerificationState.logValue) isPaymentVerified=\(currentPaymentVerificationState.isVerified) currentStatus=\(effectiveCurrentStatus.apiValue) allowedNextStatus=\(allowedNextStatus?.apiValue ?? "nil")"
        )
        if !currentPaymentVerificationState.isVerified {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=notPaymentVerified orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "결제 완료 확인 후 상태를 변경할 수 있어요."
            return
        }
        guard allowedNextStatus == nextStatus else {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=invalidTransition orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue) allowedNextStatus=\(allowedNextStatus?.apiValue ?? "nil")"
            )
            viewState.errorMessage = "현재 주문 상태에서 다음 단계만 변경할 수 있어요."
            return
        }

        Logger.shared.debug(
            "[OrderStatus] confirm orderCode=\(orderCode) next=\(nextStatus.displayTitle)"
        )
        inFlightOrderStatusUpdateOrderCodes.insert(orderCode)
        viewState.statusUpdatingOrderCodes.insert(orderCode)
        viewState.errorMessage = nil
        viewState.successMessage = nil
        applyOrders(resetErrorMessage: false, reason: "statusChangeStart")

        do {
            Logger.shared.debug(
                "[OrderStatus] submit orderCode=\(orderCode) nextStatus=\(nextStatus.apiValue)"
            )
            try await interactor.updateOrderStatus(orderCode: orderCode, status: nextStatus)
            lastSuccessfulOrderStatusByOrderCode[orderCode] = nextStatus
            applyStatus(orderCode: orderCode, status: nextStatus)
            applyOrders(resetErrorMessage: false, reason: "statusOptimistic")
            Logger.shared.debug(
                "[OrderStatus] success orderCode=\(orderCode) previousStatus=\(effectiveCurrentStatus.apiValue) nextStatus=\(nextStatus.apiValue)"
            )
            _ = await loadOrders(mode: .refresh)
            viewState.successMessage = "주문 상태가 변경되었습니다."
        } catch {
            let featureError = (error as? OrderFeatureError)
                ?? .unavailable(message: "주문 상태 변경에 실패했어요. 다시 시도해 주세요.")
            let statusCode = orderStatusFailureStatusCode(from: featureError)
            Logger.shared.error(
                "[OrderStatus] failed orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue) statusCode=\(statusCode) serverMessage=\(featureError.userMessage)"
            )
            if featureError.userMessage.contains("결제가 완료된 주문만") {
                paymentVerificationStates[orderCode] = .notVerified
            } else if !currentPaymentVerificationState.isVerified {
                paymentVerificationStates[orderCode] = .failed(featureError.userMessage)
            }
            _ = await loadOrders(mode: .refresh)
            viewState.errorMessage = featureError.userMessage.contains("결제가 완료된 주문만")
                ? "결제 완료 확인 후 상태를 변경할 수 있어요."
                : featureError.userMessage
        }

        inFlightOrderStatusUpdateOrderCodes.remove(orderCode)
        viewState.statusUpdatingOrderCodes.remove(orderCode)
        applyOrders(resetErrorMessage: false, reason: "statusChangeEnd")
    }

    private func effectiveStatus(for order: OrderSummary) -> OrderStatus {
        guard let lastSuccessfulStatus = lastSuccessfulOrderStatusByOrderCode[order.orderCode],
              order.status.isEarlierProgressStep(than: lastSuccessfulStatus) else {
            return order.status
        }
        return lastSuccessfulStatus
    }

    private func orderStatusFailureStatusCode(from error: OrderFeatureError) -> String {
        if error.userMessage.contains("요청한 주문 상태로 변경할 수 없습니다") {
            return "400"
        }
        return "unknown"
    }

    private func logOrderMappingChange(
        orderCode: String,
        previous: OrderMappingLogSnapshot?,
        snapshot: OrderMappingLogSnapshot,
        receiptExists: Bool,
        mergeSource: String
    ) {
        guard let previous else {
            Logger.shared.debugVerbose(
                "[OrderMapping] statusMerge orderCode=\(orderCode) dtoStatus=\(snapshot.dtoStatus.apiValue) localOverrideStatus=\(snapshot.localOverrideStatus?.apiValue ?? "nil") finalStatus=\(snapshot.finalStatus.apiValue) cachedPaymentState=\(snapshot.cachedPaymentState) finalPaymentState=\(snapshot.finalPaymentState) finalReceiptExists=\(receiptExists) source=\(mergeSource) statusSource=\(snapshot.statusSource)"
            )
            return
        }

        guard previous != snapshot else {
            Logger.shared.debugVerbose(
                "[OrderMapping] statusMerge orderCode=\(orderCode) dtoStatus=\(snapshot.dtoStatus.apiValue) localOverrideStatus=\(snapshot.localOverrideStatus?.apiValue ?? "nil") finalStatus=\(snapshot.finalStatus.apiValue) cachedPaymentState=\(snapshot.cachedPaymentState) finalPaymentState=\(snapshot.finalPaymentState) finalReceiptExists=\(receiptExists) source=\(mergeSource) statusSource=\(snapshot.statusSource)"
            )
            return
        }

        if previous.finalStatus != snapshot.finalStatus
            || previous.finalPaymentState != snapshot.finalPaymentState
            || previous.cachedPaymentState != snapshot.cachedPaymentState {
            Logger.shared.debug(
                "[OrderMapping] changed orderCode=\(orderCode) previousStatus=\(previous.finalStatus.apiValue) finalStatus=\(snapshot.finalStatus.apiValue) previousPaymentState=\(previous.finalPaymentState) finalPaymentState=\(snapshot.finalPaymentState)"
            )
        } else {
            Logger.shared.debugVerbose(
                "[OrderMapping] statusMerge orderCode=\(orderCode) dtoStatus=\(snapshot.dtoStatus.apiValue) localOverrideStatus=\(snapshot.localOverrideStatus?.apiValue ?? "nil") finalStatus=\(snapshot.finalStatus.apiValue) cachedPaymentState=\(snapshot.cachedPaymentState) finalPaymentState=\(snapshot.finalPaymentState) finalReceiptExists=\(receiptExists) source=\(mergeSource) statusSource=\(snapshot.statusSource)"
            )
        }
    }

    private func preparePaymentVerificationStates(for orders: [OrderSummary], requestID: Int, source: String) async {
        let orderCodes = Set(orders.map(\.orderCode))
        paymentVerificationStates = paymentVerificationStates.filter { orderCodes.contains($0.key) }
        lastSuccessfulOrderStatusByOrderCode = lastSuccessfulOrderStatusByOrderCode.filter { orderCodes.contains($0.key) }
        lastLoggedOrderMappingByOrderCode = lastLoggedOrderMappingByOrderCode.filter { orderCodes.contains($0.key) }
        noPaymentEvidenceCache = noPaymentEvidenceCache.filter { orderCodes.contains($0.key) && !$0.value.isExpired }
        var changedStatusCount = 0
        var changedPaymentCount = 0
        for order in orders {
            let existingState = paymentVerificationStates[order.orderCode]
            let cacheState = await paymentReceiptCache.state(for: order.orderCode)
            let merged = mergedPaymentVerificationState(
                for: order,
                existingState: existingState,
                cacheState: cacheState
            )
            paymentVerificationStates[order.orderCode] = merged.state
            if merged.state.isVerified {
                await paymentReceiptCache.markVerified(orderCode: order.orderCode)
            }
            let finalStatus = effectiveStatus(for: order)
            if finalStatus == order.status {
                lastSuccessfulOrderStatusByOrderCode[order.orderCode] = nil
            }
            let snapshot = OrderMappingLogSnapshot(
                dtoStatus: order.status,
                localOverrideStatus: lastSuccessfulOrderStatusByOrderCode[order.orderCode],
                finalStatus: finalStatus,
                cachedPaymentState: cacheState?.logValue ?? "none",
                finalPaymentState: merged.state.logValue
            )
            let previous = lastLoggedOrderMappingByOrderCode[order.orderCode]
            if let previous {
                if previous.finalStatus != snapshot.finalStatus {
                    changedStatusCount += 1
                }
                if previous.finalPaymentState != snapshot.finalPaymentState
                    || previous.cachedPaymentState != snapshot.cachedPaymentState {
                    changedPaymentCount += 1
                }
            }
            logOrderMappingChange(
                orderCode: order.orderCode,
                previous: previous,
                snapshot: snapshot,
                receiptExists: merged.receiptExists,
                mergeSource: merged.source
            )
            lastLoggedOrderMappingByOrderCode[order.orderCode] = snapshot
        }
        Logger.shared.debug(
            "[OrderMapping] summary requestID=\(requestID) total=\(orders.count) changedStatusCount=\(changedStatusCount) changedPaymentCount=\(changedPaymentCount) source=\(source)"
        )
    }

    private func refreshPaymentReceiptIfNeeded(orderCode: String, force: Bool) async {
        guard let order = allOrders.first(where: { $0.orderCode == orderCode }),
              !paymentReceiptRequestsInFlight.contains(orderCode) else { return }

        let currentState = paymentVerificationStates[orderCode] ?? .unchecked
        guard force || !currentState.isVerified else { return }
        let cacheState = await paymentReceiptCache.state(for: orderCode)
        let decision = autoFetchDecision(for: order, cacheState: cacheState, force: force)
        let decisionSnapshot = PaymentAutoFetchLogSnapshot(
            paidAtExists: order.paidAt != nil,
            receiptExists: order.receiptExists,
            receiptURLExists: order.receiptURL != nil,
            cacheState: cacheState?.logValue ?? "none",
            shouldFetch: decision.shouldFetch,
            reason: decision.reason
        )

        if !decision.shouldFetch {
            logPaymentAutoFetchSkip(order: order, snapshot: decisionSnapshot)
            if decision.reason == "noPaymentEvidence" {
                noPaymentEvidenceCache[orderCode] = Date().addingTimeInterval(120)
            }
            if currentState == .unchecked {
                if case .unavailable = cacheState {
                    paymentVerificationStates[orderCode] = .failed(receiptUnavailableMessage)
                    applyOrders(resetErrorMessage: false, reason: "paymentReceiptSkipped")
                }
            }
            return
        }

        let lookup = resolvePaymentReceiptLookup(for: order)
        logPaymentAutoFetchDecision(order: order, snapshot: decisionSnapshot)
        paymentReceiptRequestsInFlight.insert(orderCode)
        paymentVerificationStates[orderCode] = .checking
        applyOrders(resetErrorMessage: false, reason: "paymentReceiptStart")
        Logger.shared.debug(
            "[PaymentReceipt] request orderCode=\(order.orderCode) selectedKey=\(maskedPaymentLookupValue(lookup.selectedKey))"
        )

        do {
            let receipt = try await interactor.fetchPaymentReceipt(orderCode: lookup.selectedKey)
            let nextState = paymentVerificationState(from: receipt)
            paymentVerificationStates[orderCode] = nextState
            if nextState.isVerified {
                await paymentReceiptCache.markVerified(orderCode: orderCode, receipt: receipt)
            }
            Logger.shared.debug(
                "[PaymentReceipt] verified orderCode=\(orderCode) paymentVerificationState=\(nextState.logValue)"
            )
        } catch {
            let statusCode = paymentReceiptStatusCode(from: error)
            let message = paymentReceiptFailureMessage(from: error)
            if statusCode == "404" {
                await paymentReceiptCache.markUnavailable(orderCode: orderCode)
            }
            let cacheStateText = statusCode == "404" ? "unavailable" : "none"
            Logger.shared.warning(
                "[PaymentReceipt] unavailable orderCode=\(orderCode) statusCode=\(statusCode) message=\(message) cacheState=\(cacheStateText)"
            )
            if paymentVerificationState(from: order).isVerified {
                paymentVerificationStates[orderCode] = .verified
                Logger.shared.debug(
                    "[PaymentReceipt] receiptLookupFailedButOrderPaid orderCode=\(orderCode) statusCode=\(statusCode) evidence=\(order.paymentEvidenceSource)"
                )
            } else {
                paymentVerificationStates[orderCode] = .failed(receiptUnavailableMessage)
            }
        }

        paymentReceiptRequestsInFlight.remove(orderCode)
        applyOrders(resetErrorMessage: false, reason: "paymentReceiptEnd")
    }

    private func paymentVerificationState(from receipt: PaymentReceipt) -> PaymentVerificationState {
        receipt.isPaymentCompleted ? .verified : .notVerified
    }

    private var receiptUnavailableMessage: String {
        "결제 영수증을 확인할 수 없어요."
    }

    private func mergedPaymentVerificationState(
        for order: OrderSummary,
        existingState: PaymentVerificationState?,
        cacheState: PaymentReceiptCacheState?
    ) -> PaymentVerificationMerge {
        let serverState = paymentVerificationState(from: order)
        if serverState.isVerified {
            return PaymentVerificationMerge(
                state: .verified,
                receiptExists: order.receiptExists || order.receiptURL != nil,
                source: "ordersDTO"
            )
        }
        if case .verified = cacheState {
            return PaymentVerificationMerge(state: .verified, receiptExists: true, source: "receiptCache")
        }
        if existingState?.isVerified == true {
            return PaymentVerificationMerge(state: .verified, receiptExists: true, source: "paymentValidation")
        }
        if existingState == .checking {
            return PaymentVerificationMerge(
                state: .checking,
                receiptExists: order.receiptExists || order.receiptURL != nil,
                source: "paymentValidation"
            )
        }
        if case .unavailable = cacheState {
            return PaymentVerificationMerge(state: .failed(receiptUnavailableMessage), receiptExists: false, source: "receiptCache")
        }
        if serverState == .notVerified {
            return PaymentVerificationMerge(
                state: .notVerified,
                receiptExists: order.receiptExists || order.receiptURL != nil,
                source: "ordersDTO"
            )
        }
        if let existingState, existingState != .unchecked {
            return PaymentVerificationMerge(
                state: existingState,
                receiptExists: order.receiptExists || order.receiptURL != nil,
                source: "paymentValidation"
            )
        }
        return PaymentVerificationMerge(
            state: .unchecked,
            receiptExists: order.receiptExists || order.receiptURL != nil,
            source: "ordersDTO"
        )
    }

    private func paymentVerificationState(from order: OrderSummary) -> PaymentVerificationState {
        if order.paymentCompletionEvidence.isCompleted {
            return .verified
        }
        if order.paymentEvidenceSource == "paymentVerificationState"
            || order.paymentEvidenceSource == "paymentStatus" {
            return .notVerified
        }
        return .unchecked
    }

    private func autoFetchDecision(
        for order: OrderSummary,
        cacheState: PaymentReceiptCacheState?,
        force: Bool
    ) -> PaymentReceiptAutoFetchDecision {
        if force {
            noPaymentEvidenceCache[order.orderCode] = nil
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "forceRefresh")
        }
        if case .unavailable = cacheState {
            return PaymentReceiptAutoFetchDecision(shouldFetch: false, reason: "receiptUnavailableCached")
        }
        if noPaymentEvidenceCache[order.orderCode]?.isExpired == false {
            return PaymentReceiptAutoFetchDecision(shouldFetch: false, reason: "noPaymentEvidence")
        }
        if order.receiptExists || order.receiptURL != nil {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "receiptHintPresent")
        }
        if order.paidAt != nil {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "paidAtExists")
        }
        if hasPaymentLookupEvidence(order) {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "paymentLookupPresent")
        }
        if order.paymentStatus?.lowercased() == "paid" {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "paymentStatusPaid")
        }
        return PaymentReceiptAutoFetchDecision(shouldFetch: false, reason: "noPaymentEvidence")
    }

    private func hasPaymentLookupEvidence(_ order: OrderSummary) -> Bool {
        [
            order.paymentLookupKey,
            order.paymentID,
            order.merchantUID,
            order.impUID
        ].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func resolvePaymentReceiptLookup(for order: OrderSummary) -> PaymentReceiptLookup {
        let candidates: [(key: String?, reason: String)] = [
            (order.paymentLookupKey, "paymentLookupKeyPresent"),
            (order.paymentID, "paymentIdPresent"),
            (order.merchantUID, "merchantUidPresent"),
            (order.impUID, "impUidPresent"),
            (order.orderCode, "orderCodeFallback")
        ]
        let selected = candidates.first { candidate in
            candidate.key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } ?? (order.orderCode, "orderCodeFallback")
        let selectedKey = selected.key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? order.orderCode
        Logger.shared.debug(
            "[PaymentReceipt] resolve lookupKey orderCode=\(order.orderCode) merchantUid=\(maskedPaymentLookupValue(order.merchantUID)) impUid=\(maskedPaymentLookupValue(order.impUID)) paymentId=\(maskedPaymentLookupValue(order.paymentID)) selectedKey=\(maskedPaymentLookupValue(selectedKey)) reason=\(selected.reason)"
        )
        return PaymentReceiptLookup(selectedKey: selectedKey, reason: selected.reason)
    }

    private func logPaymentAutoFetchDecision(order: OrderSummary, snapshot: PaymentAutoFetchLogSnapshot) {
        let previous = lastLoggedPaymentAutoFetchDecisionByOrderCode[order.orderCode]
        lastLoggedPaymentAutoFetchDecisionByOrderCode[order.orderCode] = snapshot
        guard previous != snapshot else {
            Logger.shared.debugVerbose(
                "[PaymentReceipt] autoFetch decision orderCode=\(order.orderCode) paidAtExists=\(snapshot.paidAtExists) receiptExists=\(snapshot.receiptExists) receiptUrlExists=\(snapshot.receiptURLExists) cacheState=\(snapshot.cacheState) shouldFetch=\(snapshot.shouldFetch) reason=\(snapshot.reason)"
            )
            return
        }
        Logger.shared.debug(
            "[PaymentReceipt] autoFetch decision orderCode=\(order.orderCode) paidAtExists=\(snapshot.paidAtExists) receiptExists=\(snapshot.receiptExists) receiptUrlExists=\(snapshot.receiptURLExists) cacheState=\(snapshot.cacheState) shouldFetch=\(snapshot.shouldFetch) reason=\(snapshot.reason)"
        )
    }

    private func logPaymentAutoFetchSkip(order: OrderSummary, snapshot: PaymentAutoFetchLogSnapshot) {
        let previous = lastLoggedPaymentAutoFetchDecisionByOrderCode[order.orderCode]
        lastLoggedPaymentAutoFetchDecisionByOrderCode[order.orderCode] = snapshot
        guard previous != snapshot else {
            Logger.shared.debugVerbose(
                "[PaymentReceipt] skip orderCode=\(order.orderCode) reason=\(snapshot.reason)"
            )
            return
        }
        Logger.shared.debug(
            "[PaymentReceipt] skip orderCode=\(order.orderCode) reason=\(snapshot.reason)"
        )
    }

    private func maskedPaymentLookupValue(_ value: String?) -> String {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "nil"
        }
        guard value.count > 6 else {
            return "<present:\(value.count)>"
        }
        return "\(value.prefix(3))***\(value.suffix(3))"
    }

    private func paymentReceiptStatusCode(from error: Error) -> String {
        if case .notFound = error as? OrderFeatureError {
            return "404"
        }
        if case .notFound = error as? NetworkError {
            return "404"
        }
        return "unknown"
    }

    private func paymentReceiptFailureMessage(from error: Error) -> String {
        if let featureError = error as? OrderFeatureError {
            return featureError.userMessage
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    private func upsert(detail: OrderDetail) {
        let summary = makeSummary(from: detail)
        if let index = allOrders.firstIndex(where: { $0.id == detail.orderID || $0.orderCode == detail.orderCode }) {
            allOrders[index] = summary
        } else {
            allOrders.insert(summary, at: 0)
        }
    }

    private func makeSummary(from detail: OrderDetail) -> OrderSummary {
        OrderSummary(
            id: detail.orderID,
            orderCode: detail.orderCode,
            storeID: detail.storeID,
            storeName: detail.storeName,
            storeImagePath: detail.storeImagePath,
            status: detail.status,
            createdAt: detail.createdAt,
            paidAt: detail.paidAt ?? detail.paymentSummary?.paidAt,
            totalAmount: detail.totalAmount,
            itemSummaries: detail.items,
            pickupTime: detail.pickupTime,
            reviewID: detail.reviewID,
            reviewRating: detail.reviewRating,
            paymentStatus: detail.paymentSummary?.statusText,
            receiptURL: detail.paymentSummary?.receiptURL,
            receiptExists: detail.paymentSummary?.receiptURL != nil
        )
    }

    private func bindOrderStatusChanges() {
        NotificationCenter.default.publisher(for: .pikkoOrderStatusDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[OrderStatusChangeNotificationUserInfoKey.event] as? OrderStatusChangeNotification else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.apply(statusChange: event)
                }
            }
            .store(in: &cancellables)
    }

    private func bindOrderRefreshRequests() {
        NotificationCenter.default.publisher(for: .pikkoOrdersShouldRefresh)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[OrderRefreshNotificationUserInfoKey.event] as? OrderRefreshNotification else {
                    return
                }

                Task { @MainActor [weak self] in
                    await self?.handle(refreshRequest: event)
                }
            }
            .store(in: &cancellables)
    }

    private func handle(refreshRequest event: OrderRefreshNotification) async {
        if let orderID = event.orderID {
            viewState.highlightedOrderID = orderID
            hasAutoNavigatedHighlightedOrder = false
        }
        if let orderCode = event.orderCode {
            await paymentReceiptCache.markVerified(orderCode: orderCode)
            paymentVerificationStates[orderCode] = .verified
            Logger.shared.debug("[PaymentValidation] cache verified orderCode=\(orderCode)")
        }

        guard hasLoaded else { return }

        let refreshed = await loadOrders(mode: .refresh)
        guard refreshed else { return }

        let matchedOrder = allOrders.first { order in
            event.orderID.map { $0 == order.id } == true
                || event.orderCode.map { $0 == order.orderCode } == true
        }
        if matchedOrder == nil {
            viewState.successMessage = event.message ?? "주문이 접수되었습니다. 목록 반영까지 잠시 걸릴 수 있습니다."
        } else {
            viewState.successMessage = "주문 내역을 최신 상태로 새로고침했어요."
        }
    }

    private func apply(statusChange event: OrderStatusChangeNotification) {
        guard let index = allOrders.firstIndex(where: { order in
            order.orderCode == event.orderCode || event.orderID == order.id
        }) else {
            return
        }

        let existing = allOrders[index]
        allOrders[index] = OrderSummary(
            id: existing.id,
            orderCode: existing.orderCode,
            storeID: existing.storeID,
            storeName: existing.storeName,
            storeImagePath: existing.storeImagePath,
            status: event.status,
            createdAt: existing.createdAt,
            paidAt: existing.paidAt,
            totalAmount: existing.totalAmount,
            itemSummaries: existing.itemSummaries,
            pickupTime: existing.pickupTime,
            reviewID: existing.reviewID,
            reviewRating: existing.reviewRating,
            paymentLookupKey: existing.paymentLookupKey,
            paymentID: existing.paymentID,
            merchantUID: existing.merchantUID,
            impUID: existing.impUID,
            paymentStatus: existing.paymentStatus,
            paymentVerificationState: existing.paymentVerificationState,
            receiptURL: existing.receiptURL,
            receiptExists: existing.receiptExists
        )
        viewState.cancellingOrderIDs.remove(existing.id)
        applyOrders(resetErrorMessage: false, reason: "statusNotification")
    }

    private func applyStatus(orderCode: String, status: OrderStatus) {
        guard let index = allOrders.firstIndex(where: { $0.orderCode == orderCode }) else {
            return
        }

        let existing = allOrders[index]
        allOrders[index] = OrderSummary(
            id: existing.id,
            orderCode: existing.orderCode,
            storeID: existing.storeID,
            storeName: existing.storeName,
            storeImagePath: existing.storeImagePath,
            status: status,
            createdAt: existing.createdAt,
            paidAt: existing.paidAt,
            totalAmount: existing.totalAmount,
            itemSummaries: existing.itemSummaries,
            pickupTime: existing.pickupTime,
            reviewID: existing.reviewID,
            reviewRating: existing.reviewRating,
            paymentLookupKey: existing.paymentLookupKey,
            paymentID: existing.paymentID,
            merchantUID: existing.merchantUID,
            impUID: existing.impUID,
            paymentStatus: existing.paymentStatus,
            paymentVerificationState: existing.paymentVerificationState,
            receiptURL: existing.receiptURL,
            receiptExists: existing.receiptExists
        )
    }

    private func makeEmptyState() -> OrderEmptyState {
        switch viewState.selectedFilter {
        case .all:
            return OrderEmptyState(
                title: "아직 주문 내역이 없어요",
                message: "가까운 가게를 둘러보고 첫 픽업을 시작해보세요.",
                actionTitle: "가게 둘러보기",
                requiresAuthentication: false
            )
        default:
            return OrderEmptyState(
                title: "선택한 상태의 주문이 없어요",
                message: "다른 필터를 선택하거나 새로고침해 주세요.",
                actionTitle: "다시 시도",
                requiresAuthentication: false
            )
        }
    }

    private func deduplicated(_ orders: [OrderSummary]) -> [OrderSummary] {
        var seen = Set<String>()
        return orders.filter { order in
            seen.insert(order.id).inserted
        }
    }

    private func normalize(cursor: String?) -> String? {
        guard let cursor, !cursor.isEmpty, cursor != "0" else {
            return nil
        }
        return cursor
    }
}

private extension OrderPresenter {
    enum LoadingMode {
        case initial
        case refresh
        case loadMore

        var logReason: String {
            switch self {
            case .initial:
                return "initial"
            case .refresh:
                return "refresh"
            case .loadMore:
                return "loadMore"
            }
        }
    }

    struct PaymentReceiptLookup {
        let selectedKey: String
        let reason: String
    }

    struct PaymentVerificationMerge {
        let state: PaymentVerificationState
        let receiptExists: Bool
        let source: String
    }

    struct PaymentReceiptAutoFetchDecision {
        let shouldFetch: Bool
        let reason: String
    }

    struct PaymentAutoFetchLogSnapshot: Equatable {
        let paidAtExists: Bool
        let receiptExists: Bool
        let receiptURLExists: Bool
        let cacheState: String
        let shouldFetch: Bool
        let reason: String
    }

    struct OrderMappingLogSnapshot: Equatable {
        let dtoStatus: OrderStatus
        let localOverrideStatus: OrderStatus?
        let finalStatus: OrderStatus
        let cachedPaymentState: String
        let finalPaymentState: String

        var statusSource: String {
            localOverrideStatus == nil ? "server" : "localOverride"
        }
    }

    struct ReviewEligibilitySummary {
        var writable = 0
        var alreadyReviewed = 0
        var notPickedUp = 0

        mutating func record(decision: OrderReviewEligibilityDecision) {
            if decision.isWritable {
                writable += 1
            }
            if decision.alreadyReviewed {
                alreadyReviewed += 1
            }
            if decision.reason == "notPickedUp" {
                notPickedUp += 1
            }
        }
    }

    struct ReviewEligibilitySummaryLogSnapshot: Equatable {
        let total: Int
        let writable: Int
        let alreadyReviewed: Int
        let notPickedUp: Int
    }

    struct OrderViewStateLogSnapshot: Equatable {
        let status: OrderStatus
        let allowedNextStatus: OrderStatus?
        let isStatusChangeEnabled: Bool
        let isReviewWritable: Bool
    }

    struct ReviewEligibilityLogSnapshot: Equatable {
        let storeID: String
        let status: OrderStatus
        let paymentVerificationState: PaymentVerificationState
        let alreadyReviewed: Bool
        let matchedReviewID: String?
        let isWritable: Bool
        let reason: String
    }
}

private extension PaymentVerificationState {
    var logValue: String {
        switch self {
        case .unchecked:
            return "unchecked"
        case .checking:
            return "checking"
        case .verified:
            return "verified"
        case .notVerified:
            return "notVerified"
        case .failed:
            return "failed"
        }
    }
}

private extension Date {
    var isExpired: Bool {
        self <= Date()
    }
}
