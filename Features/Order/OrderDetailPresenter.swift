import Combine
import Foundation

@MainActor
final class OrderDetailPresenter: ObservableObject {
    @Published private(set) var viewState: OrderDetailViewState

    private let interactor: OrderDetailInteracting
    private let router: OrderDetailRouting
    private let mapper: OrderMapper
    private let cancelPolicyResolver = OrderCancelPolicyResolver()
    private let paymentCoordinator: OrderPaymentCoordinator
    private let dateParser = DateParser()

    private var hasLoaded = false
    private var currentCancelPolicy: OrderCancelPolicy?
    private var currentDetail: OrderDetail?
    private var cancellables = Set<AnyCancellable>()

    init(
        initialOrderID: String,
        interactor: OrderDetailInteracting,
        router: OrderDetailRouting,
        mapper: OrderMapper,
        paymentCoordinator: OrderPaymentCoordinator = .shared
    ) {
        self.viewState = OrderDetailViewState(orderID: initialOrderID)
        self.interactor = interactor
        self.router = router
        self.mapper = mapper
        self.paymentCoordinator = paymentCoordinator
        bindOrderStatusChanges()
    }

    func send(_ action: OrderDetailAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
            guard viewState.isLoading else { return }
            await loadDetail()

        case .retryTapped:
            await loadDetail()

        case .storeTapped:
            guard let storeID = viewState.storeID else { return }
            router.routeToStoreDetail(storeID: storeID)

        case .reviewTapped:
            guard viewState.isReviewActionEnabled,
                  let storeID = viewState.storeID else { return }
            let mode: ReviewComposerMode
            if let reviewID = viewState.reviewID {
                mode = .edit(reviewID: reviewID)
            } else {
                mode = .create(orderCode: viewState.orderCode)
            }
            router.routeToReviewComposer(
                context: ReviewComposerContext(
                    storeID: storeID,
                    storeName: viewState.storeName,
                    mode: mode
                )
            )

        case .resumePendingPaymentTapped:
            await resumePendingPayment()

        case .paymentBridgeResult(let result):
            await handlePaymentBridge(result)

        case .paymentBridgeDismissed:
            guard viewState.paymentBridgeContext != nil else { return }
            await handlePaymentBridge(.cancelled)

        case .cancelConfirmed:
            await cancelOrder()

        case .loginRequiredTapped:
            router.routeToAuth()
        }
    }

    private func loadDetail() async {
        viewState.isLoading = true
        viewState.errorMessage = nil

        do {
            let detail = try await interactor.fetchOrderDetail()
            apply(detail: detail)
        } catch {
            apply(error: error)
        }

        viewState.isLoading = false
    }

    private func apply(detail: OrderDetail) {
        currentDetail = detail
        viewState.orderID = detail.orderID
        viewState.orderCode = detail.orderCode
        viewState.storeID = detail.storeID
        viewState.storeName = detail.storeName
        viewState.reviewID = detail.reviewID
        viewState.storeCategoryText = detail.storeCategory
        viewState.storeCloseText = detail.storeCloseTime.map { "마감 \($0)" }
        viewState.storeImagePath = detail.storeImagePath
        viewState.statusTitle = detail.isRecoverablePendingPayment ? "결제 대기" : detail.status.displayTitle
        viewState.orderStatus = detail.status
        viewState.createdAtText = dateParser.string(from: detail.createdAt, format: "M월 d일 a h:mm")
        viewState.paidAtText = detail.paidAt.map { "결제 \($0.formatted(date: .abbreviated, time: .shortened))" }
        viewState.pickupTimeText = detail.pickupTime.map { "픽업 예상 \($0.formatted(date: .abbreviated, time: .shortened))" }
        viewState.totalPriceText = mapper.currencyText(for: detail.totalAmount)
        viewState.paymentStatusText = detail.paymentSummary?.statusText
        viewState.paymentMethodText = detail.paymentSummary?.methodText
        viewState.memoText = detail.userMemo
        viewState.items = detail.items.map {
            OrderDetailItemViewState(
                id: $0.id,
                name: $0.menuName,
                quantityText: "\($0.quantity)개",
                priceText: $0.unitPriceAmount.map(mapper.currencyText(for:)) ?? "-",
                imagePath: $0.imagePath
            )
        }
        viewState.timelineStages = makeTimelineStages(from: detail.timeline, currentStatus: detail.status)
        viewState.emptyState = nil
        viewState.hasLoadedContent = true
        applyCancelPolicy(detail)
        applyPaymentRecovery(detail)
        applyReviewCTA(detail)
    }

    private func applyPaymentRecovery(_ detail: OrderDetail) {
        viewState.isPaymentRecoveryCandidate = detail.isRecoverablePendingPayment
        viewState.paymentRecoveryTitle = detail.isRecoverablePendingPayment ? "결제 미완료" : nil
        viewState.paymentRecoveryMessage = detail.isRecoverablePendingPayment ? "결제를 완료해야 주문이 접수돼요." : nil
        viewState.paymentRecoveryPrimaryActionTitle = detail.isRecoverablePendingPayment ? "결제 이어하기" : nil
        viewState.paymentRecoverySecondaryActionTitle = detail.isRecoverablePendingPayment ? "대기 주문 정리" : nil
        if detail.isRecoverablePendingPayment {
            Logger.shared.debug("[PaymentRecovery] candidate orderCode=\(detail.orderCode) amount=\(detail.totalAmount) reason=unpaidPendingApproval")
        }
    }

    private func cancelOrder() async {
        let policy = currentCancelPolicy ?? OrderCancelPolicy(
            canShowCancelButton: false,
            canExecuteCancel: false,
            strategy: .unsupported,
            reason: .unsupportedStatus,
            userMessage: viewState.cancelDisabledReasonText,
            debugReason: "missingPolicy",
            hasPaymentIdentifier: false,
            cancelEndpointAvailable: false
        )
        Logger.shared.debug(
            "[OrderCancel] tapped orderCode=\(viewState.orderCode) strategy=\(policy.strategy.rawValue)"
        )
        guard policy.canExecuteCancel else {
            Logger.shared.debug(
                "[OrderCancel] request method=none path=none orderCode=\(viewState.orderCode) strategy=\(policy.strategy.rawValue)"
            )
            viewState.cancelErrorMessage = viewState.cancelDisabledReasonText ?? "현재 주문은 앱에서 취소할 수 없어요."
            return
        }

        viewState.isCancelling = true
        viewState.cancelErrorMessage = nil
        viewState.cancelSuccessMessage = nil

        do {
            let detail: OrderDetail
            switch policy.strategy {
            case .serverOrderCancel:
                Logger.shared.debug(
                    "[OrderCancel] request method=none path=none orderCode=\(viewState.orderCode) strategy=\(policy.strategy.rawValue)"
                )
                detail = try await interactor.cancelOrder(orderCode: viewState.orderCode)
            case .serverPaymentCancel:
                Logger.shared.debug(
                    "[OrderCancel] request method=none path=none orderCode=\(viewState.orderCode) strategy=\(policy.strategy.rawValue)"
                )
                detail = try await interactor.cancelOrder(orderCode: viewState.orderCode)
            case .localPendingCancel:
                Logger.shared.debug("[PendingOrderHide] localOnly=true orderCode=\(viewState.orderCode)")
                detail = try await interactor.cancelPendingOrderLocally(orderCode: viewState.orderCode)
            case .unsupported:
                throw OrderFeatureError.unavailable(message: policy.userMessage ?? "현재 주문은 앱에서 취소할 수 없어요.")
            }
            apply(detail: detail)
            NotificationCenter.default.post(
                name: .pikkoOrdersShouldRefresh,
                object: nil,
                userInfo: [
                    OrderRefreshNotificationUserInfoKey.event: OrderRefreshNotification(
                        orderID: detail.orderID,
                        orderCode: detail.orderCode,
                    message: policy.strategy == .localPendingCancel ? "대기 주문을 주문현황에서 숨겼어요." : "주문이 취소되었어요."
                    )
                ]
            )
            viewState.cancelSuccessMessage = policy.strategy == .localPendingCancel ? "대기 주문을 주문현황에서 숨겼어요." : "주문이 취소되었어요."
        } catch {
            let featureError = (error as? OrderFeatureError)
                ?? .unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
            Logger.shared.warning(
                "[OrderCancel] failed orderCode=\(viewState.orderCode) statusCode=unknown serverMessage=\(featureError.userMessage) strategy=unsupported"
            )
            viewState.cancelErrorMessage = cancelFailureUserMessage(from: featureError)
        }

        viewState.isCancelling = false
    }

    private func resumePendingPayment() async {
        guard let detail = currentDetail, detail.isRecoverablePendingPayment else { return }
        guard !viewState.isPaymentRecoveryInProgress else { return }
        Logger.shared.debug("[PaymentRecovery] resume tapped orderCode=\(detail.orderCode)")
        Logger.shared.debug("[PaymentRecovery] reuseExistingOrder orderCode=\(detail.orderCode) createOrderSkipped=true")
        viewState.isPaymentRecoveryInProgress = true
        viewState.cancelErrorMessage = nil
        viewState.cancelSuccessMessage = nil
        do {
            let session = try await interactor.makePendingPaymentSession(detail: detail)
            await interactor.savePendingPaymentSession(session)
            guard await paymentCoordinator.beginPayment(orderCode: detail.orderCode) else {
                viewState.cancelErrorMessage = "이미 진행 중인 결제가 있어요. 결제 상태를 확인해 주세요."
                viewState.isPaymentRecoveryInProgress = false
                return
            }
            let request = try await interactor.makePaymentRequest(pendingSession: session)
            await interactor.updatePendingPaymentSession(orderCode: detail.orderCode, state: .openingPayment, impUID: nil)
            viewState.paymentBridgeContext = CheckoutPaymentBridgeContext(
                orderID: detail.orderID,
                orderCode: detail.orderCode,
                paymentRequest: request
            )
        } catch {
            let featureError = (error as? OrderFeatureError) ?? .unavailable(message: "결제를 다시 여는 중 오류가 발생했어요.")
            viewState.cancelErrorMessage = featureError.userMessage
        }
        viewState.isPaymentRecoveryInProgress = false
    }

    private func handlePaymentBridge(_ result: CheckoutPaymentBridgeResult) async {
        guard let context = viewState.paymentBridgeContext else { return }
        viewState.paymentBridgeContext = nil
        await paymentCoordinator.endPayment(orderCode: context.orderCode)
        switch result {
        case .cancelled:
            Logger.shared.debug("[PaymentRecovery] portOne returned cancel orderCode=\(context.orderCode)")
            await interactor.updatePendingPaymentSession(orderCode: context.orderCode, state: .recoverablePending, impUID: nil)
            viewState.cancelSuccessMessage = "결제가 완료되지 않았어요. 언제든 이어서 결제할 수 있어요."
        case .failed(let message):
            Logger.shared.debug("[PaymentRecovery] portOne returned failure orderCode=\(context.orderCode)")
            await interactor.updatePendingPaymentSession(orderCode: context.orderCode, state: .recoverablePending, impUID: nil)
            viewState.cancelErrorMessage = message.isEmpty ? "결제를 완료하지 못했어요. 다시 시도해 주세요." : message
        case .missingImpUID:
            Logger.shared.debug("[PaymentRecovery] portOne returned failure orderCode=\(context.orderCode) reason=missingImpUid")
            await interactor.updatePendingPaymentSession(orderCode: context.orderCode, state: .recoverablePending, impUID: nil)
            viewState.cancelErrorMessage = "결제 완료 정보를 확인하지 못했어요. 다시 결제할 수 있어요."
        case .succeeded(let impUID, let merchantUID):
            Logger.shared.debug("[PaymentRecovery] portOne returned success orderCode=\(context.orderCode)")
            await validateRecoveredPayment(
                PaymentValidationRequest(
                    orderID: context.orderID,
                    orderCode: context.orderCode,
                    merchantUID: merchantUID ?? context.orderCode,
                    impUID: impUID,
                    success: true,
                    errorMessage: nil
                )
            )
        }
    }

    private func validateRecoveredPayment(_ request: PaymentValidationRequest) async {
        guard let orderCode = request.orderCode else { return }
        await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .validatingReceipt, impUID: request.impUID)
        Logger.shared.debug("[PaymentRecovery] validation status=start orderCode=\(orderCode)")
        do {
            _ = try await paymentCoordinator.validation(request: request) {
                try await self.interactor.validatePayment(request)
            }
            await interactor.removePendingPaymentSession(orderCode: orderCode)
            Logger.shared.debug("[PaymentRecovery] validation status=200 orderCode=\(orderCode)")
            await loadDetail()
            viewState.cancelSuccessMessage = "결제가 확인됐어요. 주문이 접수되었습니다."
        } catch let error as OrderFeatureError where error == .alreadyValidated {
            Logger.shared.debug("[PaymentRecovery] validation status=409 orderCode=\(orderCode)")
            _ = try? await interactor.fetchPaymentReceipt(orderCode: orderCode)
            _ = await interactor.refreshOrdersAfterAlreadyValidatedPayment(orderCode: orderCode)
            await interactor.removePendingPaymentSession(orderCode: orderCode)
            await loadDetail()
            viewState.cancelSuccessMessage = "이미 확인된 결제예요. 주문 내역을 새로고침했어요."
        } catch {
            Logger.shared.debug("[PaymentRecovery] validation status=failed orderCode=\(orderCode)")
            await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .validationFailed, impUID: request.impUID)
            viewState.cancelErrorMessage = "결제 확인에 실패했어요. 주문 내역에서 다시 확인해 주세요."
        }
    }

    private func applyCancelPolicy(_ detail: OrderDetail) {
        let paid = detail.paidAt != nil
            || detail.paymentSummary?.paidAt != nil
            || detail.paymentSummary?.statusText?.lowercased() == "paid"
        let policy = cancelPolicyResolver.policy(
            rawStatus: detail.status,
            mappedStatus: detail.status,
            paid: paid,
            paymentLookupKey: nil,
            paymentID: nil,
            merchantUID: nil,
            impUID: nil
        )
        currentCancelPolicy = policy
        viewState.canCancelOrder = policy.canShowCancelButton && !viewState.isCancelling
        viewState.canExecuteCancelOrder = policy.canExecuteCancel && !viewState.isCancelling
        viewState.cancelDisabledReasonText = policy.userMessage
        Logger.shared.debug(
            "[OrderCancelPolicy] orderCode=\(detail.orderCode) rawStatus=\(detail.status.apiValue) mappedStatus=\(detail.status.apiValue) paid=\(paid) evidence=\(paid ? "detailPaymentSummary" : "none") paymentId=nil impUid=nil merchantUid=nil canShowCancelButton=\(policy.canShowCancelButton) canExecuteCancel=\(policy.canExecuteCancel) reason=\(policy.reason.rawValue) cancelEndpointAvailable=\(policy.cancelEndpointAvailable) hasPaymentIdentifier=\(policy.hasPaymentIdentifier) debugReason=\(policy.debugReason)"
        )
        Logger.shared.debug(
            "[OrderCancelRender] orderCode=\(detail.orderCode) rawStatus=\(detail.status.apiValue) paid=\(paid) canShowCancelButton=\(policy.canShowCancelButton) strategy=\(policy.strategy.rawValue)"
        )
    }

    private func cancelFailureUserMessage(from error: OrderFeatureError) -> String {
        if error.userMessage.contains("결제가 완료된 주문만") {
            return "아직 결제 확인이 완료되지 않아 취소할 수 없어요."
        }
        return "주문 취소에 실패했어요. 잠시 후 다시 시도해주세요."
    }

    private func applyReviewCTA(_ detail: OrderDetail) {
        guard detail.status == .completed else {
            viewState.reviewActionTitle = nil
            viewState.isReviewActionEnabled = false
            return
        }

        if detail.reviewID != nil {
            viewState.reviewActionTitle = "리뷰 수정하기"
        } else {
            viewState.reviewActionTitle = "리뷰 작성하기"
        }
        viewState.isReviewActionEnabled = true
    }

    private func apply(error: Error) {
        let featureError = (error as? OrderFeatureError) ?? .unavailable(message: "주문 상세를 불러오지 못했어요.")
        viewState.hasLoadedContent = false
        if featureError == .notFound {
            viewState.emptyState = OrderEmptyState(
                title: "주문 반영 대기 중",
                message: "주문이 접수되었습니다. 목록 반영까지 잠시 걸릴 수 있습니다.",
                actionTitle: "다시 확인",
                requiresAuthentication: false
            )
            return
        }

        viewState.emptyState = OrderEmptyState(
            title: featureError == .authenticationRequired ? "로그인이 필요해요" : "주문 상세를 불러오지 못했어요",
            message: featureError.userMessage,
            actionTitle: featureError == .authenticationRequired ? "로그인하러 가기" : "다시 시도",
            requiresAuthentication: featureError == .authenticationRequired
        )
    }

    private func makeTimelineStages(
        from timeline: [OrderStatusTimelineEntry],
        currentStatus: OrderStatus
    ) -> [OrderStatusTimelineView.Stage] {
        let orderedStatuses: [OrderStatus] = [.pending, .accepted, .preparing, .ready, .completed]

        guard let currentIndex = currentStatus.progressStepIndex else {
            return [
                OrderStatusTimelineView.Stage(
                    id: currentStatus.displayTitle,
                    title: currentStatus.displayTitle,
                    timeText: currentStatus.isExceptionTerminal ? "주문이 종료되었어요" : "상태를 확인하고 있어요",
                    state: currentStatus.isExceptionTerminal ? .current : .upcoming
                )
            ]
        }

        return orderedStatuses.enumerated().map { index, status in
            let entry = timeline.first { $0.status == status }
            let state: OrderStatusTimelineView.StageState
            if index < currentIndex {
                state = .completed
            } else if index == currentIndex {
                state = .current
            } else {
                state = .upcoming
            }

            return OrderStatusTimelineView.Stage(
                id: status.displayTitle,
                title: status.displayTitle,
                timeText: entry?.changedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? fallbackTimelineText(for: status),
                state: state
            )
        }
    }

    private func fallbackTimelineText(for status: OrderStatus) -> String {
        switch status {
        case .pending:
            return "승인 전"
        case .accepted, .preparing, .ready, .completed:
            return "상태 대기 중"
        case .cancelled, .rejected, .failed, .unknown:
            return "확인 중"
        }
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

    private func apply(statusChange event: OrderStatusChangeNotification) {
        guard viewState.orderCode == event.orderCode || event.orderID.map({ $0 == viewState.orderID }) == true else {
            return
        }

        viewState.orderStatus = event.status
        viewState.statusTitle = event.status.displayTitle
        viewState.canCancelOrder = false
        viewState.canExecuteCancelOrder = false
        viewState.cancelDisabledReasonText = event.status.isTerminal
            ? nil
            : "매장 승인 후에는 앱에서 취소할 수 없어요."
        viewState.reviewActionTitle = event.status == .completed
            ? (viewState.reviewID == nil ? "리뷰 작성하기" : "리뷰 수정하기")
            : nil
        viewState.isReviewActionEnabled = event.status == .completed

        let timeline = viewState.timelineStages.map {
            OrderStatusTimelineEntry(
                id: $0.id,
                status: OrderStatus(displayTitle: $0.title),
                completed: $0.state != .upcoming,
                changedAt: nil
            )
        } + [
            OrderStatusTimelineEntry(
                id: event.status.displayTitle,
                status: event.status,
                completed: true,
                changedAt: Date()
            )
        ]
        viewState.timelineStages = makeTimelineStages(from: timeline, currentStatus: event.status)
    }
}

private extension OrderStatus {
    init(displayTitle: String) {
        switch displayTitle {
        case OrderStatus.pending.displayTitle:
            self = .pending
        case OrderStatus.accepted.displayTitle:
            self = .accepted
        case OrderStatus.preparing.displayTitle:
            self = .preparing
        case OrderStatus.ready.displayTitle:
            self = .ready
        case OrderStatus.completed.displayTitle:
            self = .completed
        case OrderStatus.cancelled.displayTitle:
            self = .cancelled
        case OrderStatus.rejected.displayTitle:
            self = .rejected
        case OrderStatus.failed.displayTitle:
            self = .failed
        default:
            self = .unknown(displayTitle)
        }
    }
}
