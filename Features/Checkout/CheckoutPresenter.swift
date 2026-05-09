import Foundation

@MainActor
final class CheckoutPresenter: ObservableObject {
    @Published private(set) var viewState = CheckoutViewState()

    private let interactor: CheckoutInteracting
    private let router: CheckoutRouting
    private let cartStore: CartStore
    private let paymentReceiptCache: PaymentReceiptCache
    private let paymentCoordinator: OrderPaymentCoordinator
    private var hasLoaded = false
    private var pendingValidationRequest: PaymentValidationRequest?

    init(
        interactor: CheckoutInteracting,
        router: CheckoutRouting,
        cartStore: CartStore,
        paymentReceiptCache: PaymentReceiptCache = .shared,
        paymentCoordinator: OrderPaymentCoordinator = .shared
    ) {
        self.interactor = interactor
        self.router = router
        self.cartStore = cartStore
        self.paymentReceiptCache = paymentReceiptCache
        self.paymentCoordinator = paymentCoordinator
    }

    convenience init(
        interactor: CheckoutInteracting,
        router: CheckoutRouting,
        cartStore: CartStore
    ) {
        self.init(
            interactor: interactor,
            router: router,
            cartStore: cartStore,
            paymentReceiptCache: .shared
        )
    }

    func send(_ action: CheckoutAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
            await restoreRecoverablePaymentSessionIfNeeded()
        case .pickupMemoChanged(let memo):
            viewState.pickupMemo = memo
            if !memo.isEmpty, viewState.errorMessage != nil {
                viewState.errorMessage = nil
            }
        case .primaryButtonTapped:
            if viewState.isPaymentConfigurationBlocked {
                showPaymentConfigurationGuide()
                return
            }

            if viewState.canRouteToOrderHistoryFromPrimary {
                router.routeToOrderHistory(orderID: viewState.createdOrderID)
                return
            }

            if viewState.paymentStage == .paymentValidationFailed {
                await retryPaymentValidation()
                return
            }

            if let session = viewState.recoverablePaymentSession {
                await resumePaymentSession(session)
                return
            }

            await submitOrder()
        case .orderHistoryTapped:
            guard let createdOrderID = viewState.createdOrderID else { return }
            router.routeToOrderHistory(orderID: createdOrderID)
        case .paymentBridgeResult(let result):
            await handlePaymentBridge(result)
        case .paymentBridgeDismissed:
            guard viewState.paymentBridgeContext != nil else { return }
            await handlePaymentBridge(.cancelled)
        }
    }

    private func submitOrder() async {
        guard viewState.isPrimaryEnabled, !viewState.isPrimaryLoading else { return }
        if let session = await interactor.loadRecoverablePaymentSession() {
            applyRecoverablePaymentSession(session)
            return
        }
        let previousOrderID = viewState.createdOrderID
        let previousOrderCode = viewState.createdOrderCode

        // The backend does not currently expose a re-pay contract for an unpaid order.
        // After a PortOne cancellation/failure, retry creates a new order instead of reusing
        // the previous unpaid order_code, which may not appear in GET /v1/orders.
        pendingValidationRequest = nil
        clearTransientStateForSubmit()
        setLoadingState(
            isValidatingPrice: true,
            isSubmittingOrder: false,
            isPaymentInProgress: false,
            isVerifyingPayment: false,
            title: "가격 확인 중...",
            stage: .validatingPrice
        )

        let input = CheckoutSubmissionInput(
            address: .placeholder,
            paymentMethod: .card,
            coupon: nil,
            pickupMemo: viewState.pickupMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            let validationResult = try await interactor.validatePrice(input: input)
            apply(validationResult: validationResult)

            guard validationResult.isValid else {
                setLoadingState(
                    isValidatingPrice: false,
                    isSubmittingOrder: false,
                    isPaymentInProgress: false,
                    isVerifyingPayment: false,
                    title: "주문 정보 다시 확인하기",
                    stage: .idle
                )
                viewState.isPrimaryEnabled = !viewState.isEmpty
                viewState.errorMessage = validationResult.message ?? "결제 전 확인이 필요해요."
                return
            }

            try await interactor.validatePaymentConfigurationBeforeOrderCreation()

            setLoadingState(
                isValidatingPrice: false,
                isSubmittingOrder: true,
                isPaymentInProgress: false,
                isVerifyingPayment: false,
                title: "주문 생성 중...",
                stage: .creatingOrder
            )

            let createdOrder = try await interactor.createOrder(input: input)
            let pendingSession = try await interactor.makePendingPaymentSession(
                createdOrder: createdOrder,
                state: .orderCreated,
                impUID: nil
            )
            await interactor.savePendingPaymentSession(pendingSession)
            if let previousOrderID, let previousOrderCode {
                Logger.shared.warning(
                    "Checkout retry created new order retryPolicy=create_new_order previousOrderId=\(previousOrderID) previousOrderCode=\(previousOrderCode) newOrderId=\(createdOrder.id) newOrderCode=\(createdOrder.orderCode)"
                )
            }
            viewState.createdOrderID = createdOrder.id
            viewState.createdOrderCode = createdOrder.orderCode
            viewState.totalPriceText = formatWon(createdOrder.totalPriceAmount)

            let paymentRequest: PaymentGatewayRequest
            do {
                paymentRequest = try await interactor.makePaymentRequest(createdOrder: createdOrder)
            } catch let error as CheckoutFeatureError {
                Logger.shared.warning(
                    "Checkout payment preparation failed after order creation orderCode=\(createdOrder.orderCode) orderId=\(createdOrder.id) retryPolicy=create_new_order cartRetained=true error=\(debugDescription(for: error))"
                )
                apply(featureError: error)
                return
            } catch {
                Logger.shared.warning(
                    "Checkout payment preparation failed after order creation orderCode=\(createdOrder.orderCode) orderId=\(createdOrder.id) retryPolicy=create_new_order cartRetained=true error=\(error.localizedDescription)"
                )
                setLoadingState(
                    isValidatingPrice: false,
                    isSubmittingOrder: false,
                    isPaymentInProgress: false,
                    isVerifyingPayment: false,
                    title: "주문 다시 생성하기",
                    stage: .idle
                )
                viewState.isPrimaryEnabled = !viewState.isEmpty
                viewState.errorMessage = "결제 준비 중 오류가 발생했어요. 장바구니는 유지되며 주문을 다시 생성할 수 있어요."
                return
            }
            Logger.shared.debug(
                "PortOne payment prepared orderCode=\(createdOrder.orderCode) merchantUid=\(paymentRequest.merchantUID) amount=\(paymentRequest.amount) pg=\(paymentRequest.pg) payMethod=\(paymentRequest.payMethod)"
            )
            guard await paymentCoordinator.beginPayment(orderCode: createdOrder.orderCode) else {
                applyRecoverablePaymentSession(pendingSession)
                viewState.errorMessage = "이미 진행 중인 결제가 있어요. 결제 상태를 확인해 주세요."
                return
            }
            await interactor.updatePendingPaymentSession(orderCode: createdOrder.orderCode, state: .openingPayment, impUID: nil)
            viewState.paymentBridgeContext = CheckoutPaymentBridgeContext(
                orderID: createdOrder.id,
                orderCode: createdOrder.orderCode,
                paymentRequest: paymentRequest
            )
            viewState.completionState = .none
            viewState.canRouteToOrderHistoryFromPrimary = false
            viewState.isPrimaryEnabled = false
            setLoadingState(
                isValidatingPrice: false,
                isSubmittingOrder: false,
                isPaymentInProgress: true,
                isVerifyingPayment: false,
                title: "결제 진행 중...",
                stage: .presentingPayment
            )
            viewState.successMessage = "결제 창이 열리면 결제를 완료해 주세요."
            Logger.shared.debug("[PortOne] presentPayment started")
        } catch let error as CheckoutFeatureError {
            apply(featureError: error)
        } catch {
            setLoadingState(
                isValidatingPrice: false,
                isSubmittingOrder: false,
                isPaymentInProgress: false,
                isVerifyingPayment: false,
                title: "주문 다시 생성하기",
                stage: .idle
            )
            viewState.isPrimaryEnabled = !viewState.isEmpty
            viewState.errorMessage = "주문 생성 중 알 수 없는 오류가 발생했어요."
        }
    }

    private func clearTransientStateForSubmit() {
        viewState.errorMessage = nil
        viewState.successMessage = nil
        viewState.validationIssues = []
        viewState.canRouteToOrderHistoryFromPrimary = false
        viewState.createdOrderID = nil
        viewState.createdOrderCode = nil
        viewState.paymentBridgeContext = nil
        viewState.recoverablePaymentSession = nil
        viewState.completionState = .none
        viewState.paymentStage = .idle
        applyValidationMessages()
    }

    private func apply(validationResult: CheckoutPriceValidationResult) {
        if let validatedTotalPriceAmount = validationResult.validatedTotalPriceAmount,
           validatedTotalPriceAmount > 0 {
            viewState.totalPriceText = formatWon(validatedTotalPriceAmount)
        }

        viewState.validationIssues = validationResult.issues.map { issue in
            CheckoutValidationIssueViewState(
                id: issue.id,
                menuID: issue.menuID,
                title: title(for: issue.kind),
                message: issue.message,
                isBlocking: issue.isBlocking
            )
        }
        applyValidationMessages()
    }

    private func applyValidationMessages() {
        let messagesByMenuID = Dictionary(
            viewState.validationIssues.compactMap { issue -> (String, String)? in
                guard let menuID = issue.menuID else { return nil }
                return (menuID, issue.message)
            },
            uniquingKeysWith: { first, _ in first }
        )

        viewState.items = viewState.items.map { item in
            var updated = item
            updated.validationMessage = messagesByMenuID[item.id]
            return updated
        }
    }

    private func apply(featureError: CheckoutFeatureError) {
        setLoadingState(
            isValidatingPrice: false,
            isSubmittingOrder: false,
            isPaymentInProgress: false,
            isVerifyingPayment: false,
            title: "주문 다시 생성하기",
            stage: .idle
        )
        viewState.isPrimaryEnabled = !viewState.isEmpty

        switch featureError {
        case .validation(let message),
             .businessAuthorization(let message),
             .notFound(let message),
             .unavailable(let message):
            viewState.errorMessage = message
        case .validationIssues(let issues):
            apply(
                validationResult: CheckoutPriceValidationResult(
                    validatedTotalPriceAmount: nil,
                    issues: issues,
                    message: "주문 정보를 다시 확인해 주세요."
                )
            )
            viewState.errorMessage = "주문 정보를 다시 확인해 주세요."
        case .authenticationRequired:
            viewState.errorMessage = "로그인 후 주문을 생성할 수 있어요."
            router.routeToAuth()
        case .configurationRequired:
            viewState.primaryActionTitle = "결제 설정 확인하기"
            viewState.isPaymentConfigurationBlocked = true
            viewState.isPrimaryEnabled = !viewState.isEmpty
            viewState.errorMessage = viewState.paymentConfigurationDiagnosticMessage
                ?? "PORTONE_USER_CODE 설정이 필요해요. Config/Secrets.xcconfig에 실제 PortOne 가맹점 식별코드를 넣고 Clean Build 해 주세요. 장바구니는 유지되며 설정 전에는 주문을 생성하지 않아요."
        case .alreadyValidated:
            viewState.errorMessage = "이미 확인된 결제예요. 주문 내역을 새로고침해 주세요."
        }
    }

    private func showPaymentConfigurationGuide() {
        Logger.shared.debug("[Checkout] paymentButtonState=blockedMissingConfig")
        Logger.shared.error("[Checkout] orderCreationBlocked reason=missingPortOneUserCode")
        viewState.errorMessage = viewState.paymentConfigurationDiagnosticMessage
            ?? "Config/Secrets.xcconfig에 PORTONE_USER_CODE를 실제 PortOne 가맹점 식별코드로 설정한 뒤 Clean Build 하세요."
        viewState.successMessage = nil
        viewState.primaryActionTitle = "결제 설정 확인하기"
        viewState.isPrimaryEnabled = !viewState.isEmpty
    }

    private func handlePaymentBridge(_ result: CheckoutPaymentBridgeResult) async {
        switch result {
        case .cancelled:
            Logger.shared.debug("PortOne payment canceled orderCode=\(viewState.createdOrderCode ?? "nil")")
            if let orderCode = viewState.createdOrderCode {
                await paymentCoordinator.endPayment(orderCode: orderCode)
                await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .recoverablePending, impUID: nil)
                await restoreRecoverablePaymentSessionIfNeeded()
            }
            configureRetryablePaymentState(
                stage: .paymentCanceled,
                message: "결제가 취소되었습니다. 장바구니는 유지됩니다."
            )
        case .failed(let message):
            Logger.shared.debug("PortOne payment failed orderCode=\(viewState.createdOrderCode ?? "nil")")
            if let orderCode = viewState.createdOrderCode {
                await paymentCoordinator.endPayment(orderCode: orderCode)
                await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .validationFailed, impUID: nil)
                await restoreRecoverablePaymentSessionIfNeeded()
            }
            configureRetryablePaymentState(
                stage: .paymentFailed,
                message: message.isEmpty
                    ? "결제를 완료하지 못했어요. 장바구니는 유지되며 다시 결제할 수 있어요."
                    : message
            )
        case .missingImpUID:
            Logger.shared.debug("PortOne payment callback missing imp_uid orderCode=\(viewState.createdOrderCode ?? "nil")")
            if let orderCode = viewState.createdOrderCode {
                await paymentCoordinator.endPayment(orderCode: orderCode)
                await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .recoverablePending, impUID: nil)
                await restoreRecoverablePaymentSessionIfNeeded()
            }
            configureRetryablePaymentState(
                stage: .paymentFailed,
                message: "결제 완료 정보를 확인하지 못했어요. 장바구니는 유지되며 다시 결제할 수 있어요."
            )
        case .succeeded(let impUID, let merchantUID):
            Logger.shared.debug(
                "[Payment] callback received orderCode=\(viewState.createdOrderCode ?? "nil") success=true impUid=\(impUID) merchantUid=\(merchantUID ?? "nil")"
            )
            let validationRequest = PaymentValidationRequest(
                orderID: viewState.createdOrderID,
                orderCode: viewState.createdOrderCode,
                merchantUID: merchantUID ?? viewState.createdOrderCode,
                impUID: impUID,
                success: true,
                errorMessage: nil
            )
            if let orderCode = validationRequest.orderCode {
                await paymentCoordinator.endPayment(orderCode: orderCode)
                await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .paymentReturned, impUID: impUID)
            }
            viewState.paymentBridgeContext = nil
            viewState.errorMessage = nil
            viewState.successMessage = nil
            viewState.isPrimaryEnabled = false
            viewState.canRouteToOrderHistoryFromPrimary = false
            viewState.paymentStage = .paymentCallbackReceived
            await validatePaymentWithServer(validationRequest)
        }
    }

    private func setLoadingState(
        isValidatingPrice: Bool,
        isSubmittingOrder: Bool,
        isPaymentInProgress: Bool,
        isVerifyingPayment: Bool,
        title: String,
        stage: CheckoutPaymentStage
    ) {
        viewState.isValidatingPrice = isValidatingPrice
        viewState.isSubmittingOrder = isSubmittingOrder
        viewState.isPaymentInProgress = isPaymentInProgress
        viewState.isVerifyingPayment = isVerifyingPayment
        viewState.isPrimaryLoading = isValidatingPrice || isSubmittingOrder || isPaymentInProgress || isVerifyingPayment
        viewState.primaryActionTitle = title
        viewState.paymentStage = stage
    }

    private func configureRetryablePaymentState(stage: CheckoutPaymentStage, message: String) {
        viewState.paymentBridgeContext = nil
        viewState.isValidatingPrice = false
        viewState.isSubmittingOrder = false
        viewState.isPaymentInProgress = false
        viewState.isVerifyingPayment = false
        viewState.isPrimaryLoading = false
        viewState.isPrimaryEnabled = !viewState.isEmpty
        viewState.canRouteToOrderHistoryFromPrimary = false
        viewState.completionState = .none
        viewState.paymentStage = stage
        viewState.primaryActionTitle = "결제 다시 시도하기"
        viewState.errorMessage = message
        viewState.successMessage = nil
    }

    private func restoreRecoverablePaymentSessionIfNeeded() async {
        guard viewState.recoverablePaymentSession == nil,
              let session = await interactor.loadRecoverablePaymentSession() else {
            return
        }
        applyRecoverablePaymentSession(session)
    }

    private func applyRecoverablePaymentSession(_ session: PendingPaymentSession) {
        viewState.createdOrderID = session.orderID
        viewState.createdOrderCode = session.orderCode
        viewState.totalPriceText = formatWon(session.totalPriceAmount)
        viewState.recoverablePaymentSession = session
        viewState.paymentStage = .recoverablePending
        viewState.completionState = .none
        viewState.paymentBridgeContext = nil
        viewState.isPrimaryEnabled = true
        viewState.isPrimaryLoading = false
        viewState.isPaymentInProgress = false
        viewState.isVerifyingPayment = false
        viewState.canRouteToOrderHistoryFromPrimary = false
        viewState.primaryActionTitle = session.hasReturnedReceipt ? "결제 상태 확인" : "결제 이어하기"
        viewState.successMessage = nil
        viewState.errorMessage = "완료되지 않은 결제가 있어요. 중복 주문을 만들지 않고 이어서 확인할 수 있어요."
    }

    private func resumePaymentSession(_ session: PendingPaymentSession) async {
        viewState.errorMessage = nil
        viewState.successMessage = nil
        if let impUID = session.impUID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !impUID.isEmpty {
            await validatePaymentWithServer(
                PaymentValidationRequest(
                    orderID: session.orderID,
                    orderCode: session.orderCode,
                    merchantUID: session.orderCode,
                    impUID: impUID,
                    success: true,
                    errorMessage: nil
                )
            )
            return
        }

        do {
            guard await paymentCoordinator.beginPayment(orderCode: session.orderCode) else {
                viewState.errorMessage = "이미 진행 중인 결제가 있어요. 결제 상태를 확인해 주세요."
                return
            }
            let paymentRequest = try await interactor.makePaymentRequest(pendingSession: session)
            await interactor.updatePendingPaymentSession(orderCode: session.orderCode, state: .openingPayment, impUID: nil)
            viewState.paymentBridgeContext = CheckoutPaymentBridgeContext(
                orderID: session.orderID ?? session.orderCode,
                orderCode: session.orderCode,
                paymentRequest: paymentRequest
            )
            viewState.recoverablePaymentSession = nil
            setLoadingState(
                isValidatingPrice: false,
                isSubmittingOrder: false,
                isPaymentInProgress: true,
                isVerifyingPayment: false,
                title: "결제 진행 중...",
                stage: .presentingPayment
            )
        } catch let error as CheckoutFeatureError {
            apply(featureError: error)
        } catch {
            viewState.errorMessage = "결제를 다시 여는 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    private func retryPaymentValidation() async {
        guard let validationRequest = pendingValidationRequest else {
            configureRetryablePaymentState(
                stage: .paymentFailed,
                message: "결제 확인에 필요한 정보를 찾지 못했어요. 장바구니는 유지되며 다시 결제할 수 있어요."
            )
            return
        }

        await validatePaymentWithServer(validationRequest)
    }

    private func validatePaymentWithServer(_ validationRequest: PaymentValidationRequest) async {
        pendingValidationRequest = validationRequest
        if let orderCode = validationRequest.orderCode {
            await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .validatingReceipt, impUID: validationRequest.impUID)
        }
        Logger.shared.debug(
            "[PaymentValidation] request method=POST path=/v1/payments/validation orderCode=\(validationRequest.orderCode ?? "nil") merchantUid=\(validationRequest.merchantUID ?? "nil") impUid=\(validationRequest.impUID) body={\"imp_uid\":\"<present:\(!validationRequest.impUID.isEmpty)>\"}"
        )
        setLoadingState(
            isValidatingPrice: false,
            isSubmittingOrder: false,
            isPaymentInProgress: false,
            isVerifyingPayment: true,
            title: "결제 확인 중...",
            stage: .validatingPayment
        )

        do {
            let receipt = try await paymentCoordinator.validation(request: validationRequest) {
                try await self.interactor.validatePayment(validationRequest)
            }
            var receiptConfirmsPayment = true
            if let orderCode = receipt.orderCode ?? validationRequest.orderCode {
                await paymentReceiptCache.markVerified(orderCode: orderCode)
                await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .validationSucceeded, impUID: validationRequest.impUID)
                Logger.shared.debug("[PaymentValidation] cache verified orderCode=\(orderCode)")
                receiptConfirmsPayment = await refreshPaymentReceiptAfterValidation(orderCode: orderCode)
                await interactor.removePendingPaymentSession(orderCode: orderCode)
            }
            cartStore.clear()
            pendingValidationRequest = nil

            viewState.isSubmittingOrder = false
            viewState.isVerifyingPayment = false
            viewState.isPrimaryLoading = false
            viewState.isPrimaryEnabled = false
            viewState.completionState = receiptConfirmsPayment ? .paymentValidated : .validationPending
            viewState.paymentStage = .paymentCompleted
            viewState.createdOrderID = receipt.orderID ?? viewState.createdOrderID
            viewState.createdOrderCode = receipt.orderCode ?? viewState.createdOrderCode
            viewState.primaryActionTitle = "결제 확인 완료"
            viewState.successMessage = receiptConfirmsPayment
                ? "결제가 확인됐어요. 주문이 접수되었고, 목록 반영까지 잠시 걸릴 수 있습니다."
                : "결제 검증은 접수되었지만 영수증 조회가 지연되고 있어요. 주문 내역을 새로고침해 주세요."
            postOrderRefreshRequested()
            Logger.shared.debug(
                "[PaymentValidation] success orderCode=\(viewState.createdOrderCode ?? "nil") response=paymentIDExists:\(receipt.paymentID != nil), orderIDExists:\(receipt.orderID != nil)"
            )
        } catch let error as CheckoutFeatureError {
            if error == .alreadyValidated {
                await handleAlreadyValidatedPayment(validationRequest)
                return
            }
            applyFailedValidationState(for: error, validationRequest: validationRequest)
        } catch {
            applyFailedValidationState(
                message: "결제 확인에 실패했습니다. 결제가 실제로 완료되었을 수 있으니 잠시 후 주문 내역을 확인하거나 고객센터에 문의해주세요.",
                validationRequest: validationRequest,
                debugError: error
            )
        }
    }

    private func refreshPaymentReceiptAfterValidation(orderCode: String) async -> Bool {
        Logger.shared.debug(
            "[PaymentReceipt] resolve lookupKey orderCode=\(orderCode) merchantUid=nil impUid=nil paymentId=nil selectedKey=\(orderCode) reason=orderCodeFallback"
        )
        Logger.shared.debug(
            "[PaymentReceipt] request orderCode=\(orderCode) selectedKey=\(orderCode)"
        )
        do {
            let receipt = try await interactor.fetchPaymentReceipt(orderCode: orderCode)
            await paymentReceiptCache.markVerified(orderCode: orderCode, receipt: receipt)
            Logger.shared.debug(
                "[PaymentReceipt] success orderCode=\(orderCode) receiptExists=true paymentStatus=\(receipt.status) paidAtExists=\(receipt.paidAt != nil)"
            )
            return receipt.isPaymentCompleted
        } catch {
            let statusCode = paymentReceiptStatusCode(from: error)
            if statusCode == "404" {
                await paymentReceiptCache.markUnavailable(orderCode: orderCode)
            }
            let cacheState = statusCode == "404" ? "unavailable" : "none"
            Logger.shared.warning(
                "[PaymentReceipt] unavailable orderCode=\(orderCode) statusCode=\(statusCode) message=\(paymentReceiptFailureMessage(from: error)) cacheState=\(cacheState)"
            )
            return false
        }
    }

    private func handleAlreadyValidatedPayment(_ validationRequest: PaymentValidationRequest) async {
        guard let orderCode = validationRequest.orderCode else {
            applyFailedValidationState(
                message: "이미 확인된 결제예요. 주문 내역을 새로고침해 주세요.",
                validationRequest: validationRequest
            )
            return
        }
        await paymentReceiptCache.markVerified(orderCode: orderCode)
        let receiptConfirmsPayment = await refreshPaymentReceiptAfterValidation(orderCode: orderCode)
        let orderListConfirmsPayment = receiptConfirmsPayment
            ? true
            : await interactor.refreshOrdersAfterAlreadyValidatedPayment(orderCode: orderCode)
        if orderListConfirmsPayment {
            await interactor.removePendingPaymentSession(orderCode: orderCode)
            cartStore.clear()
            pendingValidationRequest = nil
            viewState.isVerifyingPayment = false
            viewState.isPrimaryLoading = false
            viewState.isPrimaryEnabled = false
            viewState.completionState = .paymentValidated
            viewState.paymentStage = .paymentCompleted
            viewState.primaryActionTitle = "결제 확인 완료"
            viewState.errorMessage = nil
            viewState.successMessage = "이미 확인된 결제예요. 주문 내역에 반영했습니다."
            postOrderRefreshRequested()
        } else {
            await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .recoverablePending, impUID: validationRequest.impUID)
            applyFailedValidationState(
                message: "이미 처리된 결제예요. 주문 내역을 새로고침해 주세요.",
                validationRequest: validationRequest
            )
        }
    }

    private func paymentReceiptStatusCode(from error: Error) -> String {
        if case .notFound = error as? CheckoutFeatureError {
            return "404"
        }
        return "unknown"
    }

    private func paymentReceiptFailureMessage(from error: Error) -> String {
        if let checkoutError = error as? CheckoutFeatureError {
            switch checkoutError {
            case .validation(let message),
                 .businessAuthorization(let message),
                 .notFound(let message),
                 .unavailable(let message):
                return message
            case .validationIssues:
                return "결제 정보를 다시 확인해 주세요."
            case .authenticationRequired:
                return "로그인 후 결제를 확인할 수 있어요."
            case .configurationRequired:
                return "앱 설정을 확인해 주세요."
            case .alreadyValidated:
                return "이미 확인된 결제예요."
            }
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }

    private func applyFailedValidationState(
        for error: CheckoutFeatureError,
        validationRequest: PaymentValidationRequest
    ) {
        switch error {
        case .authenticationRequired:
            router.routeToAuth()
        case .configurationRequired:
            break
        case .alreadyValidated:
            Logger.shared.debug(
                "[PaymentValidation] alreadyValidated orderCode=\(validationRequest.orderCode ?? "nil") body={\"imp_uid\":\"<present:\(!validationRequest.impUID.isEmpty)>\"}"
            )
        case .validation(let featureMessage),
             .businessAuthorization(let featureMessage),
             .notFound(let featureMessage),
             .unavailable(let featureMessage):
            Logger.shared.warning(
                "[PaymentValidation] failed orderCode=\(validationRequest.orderCode ?? "nil") statusCode=unknown message=\(featureMessage) body={\"imp_uid\":\"<present:\(!validationRequest.impUID.isEmpty)>\"}"
            )
        case .validationIssues:
            Logger.shared.warning(
                "[PaymentValidation] failed orderCode=\(validationRequest.orderCode ?? "nil") statusCode=unknown message=validationIssues body={\"imp_uid\":\"<present:\(!validationRequest.impUID.isEmpty)>\"}"
            )
        }

        applyFailedValidationState(
            message: safeValidationFailureMessage(for: error),
            validationRequest: validationRequest
        )
    }

    private func applyFailedValidationState(
        message: String,
        validationRequest: PaymentValidationRequest? = nil,
        debugError: Error? = nil
    ) {
        if let validationRequest, let debugError {
            Logger.shared.warning(
                "[PaymentValidation] failed orderCode=\(validationRequest.orderCode ?? "nil") statusCode=unknown message=\(debugError.localizedDescription) body={\"imp_uid\":\"<present:\(!validationRequest.impUID.isEmpty)>\"}"
            )
        }
        if let orderCode = validationRequest?.orderCode {
            Task {
                await interactor.updatePendingPaymentSession(orderCode: orderCode, state: .validationFailed, impUID: validationRequest?.impUID)
            }
        }
        viewState.paymentBridgeContext = nil
        viewState.isValidatingPrice = false
        viewState.isSubmittingOrder = false
        viewState.isPaymentInProgress = false
        viewState.isVerifyingPayment = false
        viewState.isPrimaryLoading = false
        viewState.isPrimaryEnabled = !viewState.isEmpty
        viewState.canRouteToOrderHistoryFromPrimary = false
        viewState.completionState = .none
        viewState.paymentStage = .paymentValidationFailed
        viewState.primaryActionTitle = "결제 확인 재시도"
        viewState.errorMessage = message
        viewState.successMessage = nil
    }

    private func safeValidationFailureMessage(for error: CheckoutFeatureError) -> String {
        switch error {
        case .authenticationRequired:
            return "결제 확인 중 세션이 만료되었어요. 결제가 실제로 완료되었을 수 있으니 다시 로그인한 뒤 주문 내역을 확인해 주세요."
        case .configurationRequired:
            return "앱 결제 설정 문제로 결제 확인에 실패했습니다. 결제가 실제로 완료되었을 수 있으니 잠시 후 주문 내역을 확인하거나 고객센터에 문의해주세요."
        case .alreadyValidated:
            return "이미 확인된 결제예요. 주문 내역을 새로고침해 주세요."
        case .validation,
             .businessAuthorization,
             .notFound,
             .unavailable,
             .validationIssues:
            return "결제 확인에 실패했습니다. 결제가 실제로 완료되었을 수 있으니 잠시 후 주문 내역을 확인하거나 고객센터에 문의해주세요."
        }
    }

    private func postOrderRefreshRequested() {
        NotificationCenter.default.post(
            name: .pikkoOrdersShouldRefresh,
            object: nil,
            userInfo: [
                OrderRefreshNotificationUserInfoKey.event: OrderRefreshNotification(
                    orderID: viewState.createdOrderID,
                    orderCode: viewState.createdOrderCode,
                    message: "주문이 접수되었습니다. 목록 반영까지 잠시 걸릴 수 있습니다."
                )
            ]
        )
    }

    private func debugDescription(for error: CheckoutFeatureError) -> String {
        switch error {
        case .validation(let message),
             .businessAuthorization(let message),
             .notFound(let message),
             .unavailable(let message):
            return message
        case .validationIssues(let issues):
            return "validationIssues(count=\(issues.count))"
        case .authenticationRequired:
            return "authenticationRequired"
        case .configurationRequired:
            return "configurationRequired"
        case .alreadyValidated:
            return "alreadyValidated"
        }
    }

    private func title(for kind: CheckoutPriceValidationIssue.Kind) -> String {
        switch kind {
        case .priceChanged:
            return "가격 변경"
        case .soldOut:
            return "품절"
        case .menuUnavailable:
            return "메뉴 확인 필요"
        case .storeClosed:
            return "가게 상태 확인 필요"
        case .invalidCoupon:
            return "쿠폰 확인 필요"
        case .unknown:
            return "주문 확인 필요"
        }
    }

    private func formatWon(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ko_KR")
        return "\(formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")원"
    }
}
