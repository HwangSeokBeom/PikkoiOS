import Combine
import Foundation

@MainActor
final class OrderPresenter: ObservableObject {
    @Published private(set) var viewState = OrderViewState()

    private let interactor: OrderInteracting
    private let router: OrderRouting
    private let paymentReceiptCache: PaymentReceiptCache
    private let transitionPolicy = OrderStatusTransitionPolicy()
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
            applyOrders(resetErrorMessage: false)
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
            await merge(page: page, mode: mode)
            applyOrders(resetErrorMessage: true)
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

    private func merge(page: CursorPage<OrderSummary>, mode: LoadingMode) async {
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
        await preparePaymentVerificationStates(for: allOrders)
    }

    private func applyOrders(resetErrorMessage: Bool) {
        let filteredOrders = allOrders.filter { viewState.selectedFilter.includes(status: $0.status) }
        viewState.orders = filteredOrders.map(mapListItem)

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
        let isCancelEnabled = transitionPolicy.canCancel(status: currentStatus)
        let isReviewWritable = transitionPolicy.reviewWritable(status: currentStatus, reviewID: order.reviewID)
        let reviewDisabledReasonText = transitionPolicy.reviewDisabledReason(status: currentStatus, reviewID: order.reviewID)

        Logger.shared.debug(
            "[OrderViewState] cell orderCode=\(order.orderCode) status=\(currentStatus.apiValue) next=\(allowedNextStatus?.apiValue ?? "nil") isStatusChangeEnabled=\(transitionDecision.isStatusChangeEnabled) isCancelEnabled=\(isCancelEnabled) isReviewWritable=\(isReviewWritable)"
        )

        return OrderListItemViewState(
            id: order.id,
            orderCode: order.orderCode,
            storeName: order.storeName,
            storeImagePath: order.storeImagePath,
            status: currentStatus,
            statusTitle: currentStatus.displayTitle,
            currentStatus: currentStatus,
            currentStatusTitle: currentStatus.displayTitle,
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
            canCancel: isCancelEnabled,
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
            canRefreshPaymentReceipt: paymentVerificationState.shouldShowRefreshAction,
            isCancelEnabled: isCancelEnabled,
            isReviewWritable: isReviewWritable,
            reviewDisabledReasonText: reviewDisabledReasonText,
            isPastOrder: currentStatus.isTerminal,
            canWriteReview: isReviewWritable
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

    private func transitionDecision(
        orderCode: String,
        currentStatus: OrderStatus,
        paymentVerificationState: PaymentVerificationState
    ) -> OrderStatusTransitionDecision {
        let decision = transitionPolicy.decision(
            currentStatus: currentStatus,
            paymentVerificationState: paymentVerificationState
        )
        Logger.shared.debug(
            "[OrderStatus] allowedTransition orderCode=\(orderCode) currentStatus=\(currentStatus.apiValue) allowedNextStatus=\(decision.allowedNextStatus?.apiValue ?? "nil") paymentVerificationState=\(paymentVerificationState.logValue)"
        )
        return decision
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
        guard let order = allOrders.first(where: { $0.id == orderID }),
              transitionPolicy.canCancel(status: effectiveStatus(for: order)),
              !viewState.cancellingOrderIDs.contains(orderID) else { return }

        viewState.cancellingOrderIDs.insert(orderID)
        viewState.errorMessage = nil
        viewState.successMessage = nil
        applyOrders(resetErrorMessage: false)

        do {
            let detail = try await interactor.cancelOrder(orderCode: order.orderCode)
            applyStatus(orderCode: order.orderCode, status: .cancelled)
            if detail.orderID != detail.orderCode || detail.storeID.isEmpty == false {
                upsert(detail: detail)
            }
            viewState.successMessage = "주문이 취소되었어요."
        } catch {
            let featureError = (error as? OrderFeatureError)
                ?? .unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
            viewState.errorMessage = featureError.userMessage
        }

        viewState.cancellingOrderIDs.remove(orderID)
        applyOrders(resetErrorMessage: false)
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
            applyOrders(resetErrorMessage: false)
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
            "[OrderStatus] selectionChanged orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) selectedNextStatus=\(nextStatus.apiValue) isValidSelection=\(isValidSelection)"
        )
        if effectiveCurrentStatus.requiresPaymentVerification(to: nextStatus),
           !currentPaymentVerificationState.isVerified {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=notPaymentVerified orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "결제 검증 완료 후 상태 변경이 가능합니다."
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
            applyOrders(resetErrorMessage: false)
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
        if let serverAllowedNextStatus = effectiveCurrentStatus.allowedNextStatus,
           effectiveCurrentStatus.requiresPaymentVerification(to: serverAllowedNextStatus),
           !currentPaymentVerificationState.isVerified {
            Logger.shared.debug(
                "[OrderStatus] requestSkipped reason=notPaymentVerified orderCode=\(orderCode) currentStatus=\(effectiveCurrentStatus.apiValue) attemptedNextStatus=\(nextStatus.apiValue)"
            )
            viewState.errorMessage = "결제 검증 완료 후 상태 변경이 가능합니다."
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
        applyOrders(resetErrorMessage: false)

        do {
            Logger.shared.debug(
                "[OrderStatus] request PUT orderCode=\(orderCode) body={\"nextStatus\":\"\(nextStatus.apiValue)\"}"
            )
            try await interactor.updateOrderStatus(orderCode: orderCode, status: nextStatus)
            lastSuccessfulOrderStatusByOrderCode[orderCode] = nextStatus
            applyStatus(orderCode: orderCode, status: nextStatus)
            applyOrders(resetErrorMessage: false)
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
            viewState.errorMessage = featureError.userMessage
        }

        inFlightOrderStatusUpdateOrderCodes.remove(orderCode)
        viewState.statusUpdatingOrderCodes.remove(orderCode)
        applyOrders(resetErrorMessage: false)
    }

    private func effectiveStatus(for order: OrderSummary) -> OrderStatus {
        guard let lastSuccessfulStatus = lastSuccessfulOrderStatusByOrderCode[order.orderCode],
              order.status.isEarlierProgressStep(than: lastSuccessfulStatus) else {
            return order.status
        }
        return lastSuccessfulStatus
    }

    private func statusSource(for order: OrderSummary) -> String {
        effectiveStatus(for: order) == order.status ? "server" : "lastSuccessfulLocal"
    }

    private func orderStatusFailureStatusCode(from error: OrderFeatureError) -> String {
        if error.userMessage.contains("요청한 주문 상태로 변경할 수 없습니다") {
            return "400"
        }
        return "unknown"
    }

    private func preparePaymentVerificationStates(for orders: [OrderSummary]) async {
        let orderCodes = Set(orders.map(\.orderCode))
        paymentVerificationStates = paymentVerificationStates.filter { orderCodes.contains($0.key) }
        lastSuccessfulOrderStatusByOrderCode = lastSuccessfulOrderStatusByOrderCode.filter { orderCodes.contains($0.key) }
        for order in orders {
            let existingState = paymentVerificationStates[order.orderCode]
            let cacheState = await paymentReceiptCache.state(for: order.orderCode)
            Logger.shared.debug(
                "[OrderMapping] receiptCache orderCode=\(order.orderCode) cacheState=\(cacheState?.logValue ?? "none")"
            )
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
            Logger.shared.debug(
                "[OrderMapping] merged orderCode=\(order.orderCode) orderStatus=\(order.status.apiValue) finalPaymentVerificationState=\(merged.state.logValue) finalReceiptExists=\(merged.receiptExists) source=\(merged.source) orderStatusSource=server"
            )
            Logger.shared.debug(
                "[OrderMapping] statusMerge orderCode=\(order.orderCode) dtoStatus=\(order.status.apiValue) cachedPaymentState=\(cacheState?.logValue ?? "none") finalStatus=\(finalStatus.apiValue) finalPaymentState=\(merged.state.logValue) statusSource=\(statusSource(for: order))"
            )
        }
    }

    private func refreshPaymentReceiptIfNeeded(orderCode: String, force: Bool) async {
        guard let order = allOrders.first(where: { $0.orderCode == orderCode }),
              !paymentReceiptRequestsInFlight.contains(orderCode) else { return }

        let currentState = paymentVerificationStates[orderCode] ?? .unchecked
        guard force || !currentState.isVerified else { return }
        let lookup = resolvePaymentReceiptLookup(for: order)
        let cacheState = await paymentReceiptCache.state(for: orderCode)
        let decision = autoFetchDecision(for: order, cacheState: cacheState, force: force)
        Logger.shared.debug(
            "[PaymentReceipt] autoFetch decision orderCode=\(order.orderCode) paidAtExists=\(order.paidAt != nil) receiptExists=\(order.receiptExists) cacheState=\(cacheState?.logValue ?? "none") shouldFetch=\(decision.shouldFetch) reason=\(decision.reason)"
        )

        if !decision.shouldFetch {
            if currentState == .unchecked {
                if case .unavailable = cacheState {
                    paymentVerificationStates[orderCode] = .failed(receiptUnavailableMessage)
                }
                applyOrders(resetErrorMessage: false)
            }
            return
        }

        paymentReceiptRequestsInFlight.insert(orderCode)
        paymentVerificationStates[orderCode] = .checking
        applyOrders(resetErrorMessage: false)
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
            if statusCode == "404" {
                await paymentReceiptCache.markUnavailable(orderCode: orderCode)
            }
            Logger.shared.warning(
                "[PaymentReceipt] failed selectedKey=\(lookup.selectedKey) statusCode=\(statusCode) fallback=receiptUnavailable"
            )
            paymentVerificationStates[orderCode] = .failed(receiptUnavailableMessage)
        }

        paymentReceiptRequestsInFlight.remove(orderCode)
        applyOrders(resetErrorMessage: false)
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
        let rawState = order.paymentVerificationState?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch rawState {
        case "verified":
            return .verified
        case "notverified", "not_verified", "failed", "failure":
            return .notVerified
        default:
            break
        }

        if order.paymentStatus?.lowercased() == "paid", order.paidAt != nil {
            return .verified
        }
        return .unchecked
    }

    private func autoFetchDecision(
        for order: OrderSummary,
        cacheState: PaymentReceiptCacheState?,
        force: Bool
    ) -> PaymentReceiptAutoFetchDecision {
        if force {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "forceRefresh")
        }
        if case .unavailable = cacheState {
            return PaymentReceiptAutoFetchDecision(shouldFetch: false, reason: "receiptUnavailableCached")
        }
        if order.receiptExists || order.receiptURL != nil {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "receiptHintPresent")
        }
        if order.paidAt != nil {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "paidAtExists")
        }
        if order.paymentStatus?.lowercased() == "paid" {
            return PaymentReceiptAutoFetchDecision(shouldFetch: true, reason: "paymentStatusPaid")
        }
        return PaymentReceiptAutoFetchDecision(shouldFetch: false, reason: "noPaymentEvidence")
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
        return "unknown"
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
        applyOrders(resetErrorMessage: false)
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
