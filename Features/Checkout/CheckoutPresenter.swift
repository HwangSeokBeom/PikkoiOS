import Foundation

@MainActor
final class CheckoutPresenter: ObservableObject {
    @Published private(set) var viewState = CheckoutViewState()

    private let interactor: CheckoutInteracting
    private let router: CheckoutRouting
    private let cartStore: CartStore
    private var hasLoaded = false

    init(
        interactor: CheckoutInteracting,
        router: CheckoutRouting,
        cartStore: CartStore
    ) {
        self.interactor = interactor
        self.router = router
        self.cartStore = cartStore
    }

    func send(_ action: CheckoutAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
        case .pickupMemoChanged(let memo):
            viewState.pickupMemo = memo
            if !memo.isEmpty, viewState.errorMessage != nil {
                viewState.errorMessage = nil
            }
        case .primaryButtonTapped:
            if viewState.canRouteToOrderHistoryFromPrimary {
                router.routeToOrderHistory(orderID: viewState.createdOrderID)
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

        clearTransientStateForSubmit()
        setLoadingState(
            isValidatingPrice: true,
            isSubmittingOrder: false,
            title: "가격 확인 중..."
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
                    title: "주문 정보 다시 확인하기"
                )
                viewState.isPrimaryEnabled = !viewState.isEmpty
                viewState.errorMessage = validationResult.message ?? "결제 전 확인이 필요해요."
                return
            }

            setLoadingState(
                isValidatingPrice: false,
                isSubmittingOrder: true,
                title: "주문 생성 중..."
            )

            let createdOrder = try await interactor.createOrder(input: input)
            viewState.createdOrderID = createdOrder.id
            viewState.createdOrderCode = createdOrder.orderCode
            viewState.isValidatingPrice = false
            viewState.isSubmittingOrder = false
            viewState.isPrimaryLoading = false
            viewState.totalPriceText = formatWon(createdOrder.totalPriceAmount)

            if let paymentContext = makePaymentBridgeContext(from: createdOrder) {
                viewState.paymentBridgeContext = paymentContext
                viewState.completionState = .none
                viewState.canRouteToOrderHistoryFromPrimary = false
                viewState.isPrimaryEnabled = false
                viewState.primaryActionTitle = "결제 진행 중..."
                viewState.successMessage = "결제 창이 열리면 결제를 완료해 주세요."
            } else if createdOrder.paymentBridgePayload != nil {
                configurePendingOrderHistoryState(
                    message: "결제 창을 열지 못했어요. 주문 내역에서 상태를 확인해 주세요."
                )
            } else {
                cartStore.clear()
                viewState.completionState = .orderCreated
                viewState.canRouteToOrderHistoryFromPrimary = false
                viewState.isPrimaryEnabled = false
                viewState.primaryActionTitle = "주문 생성 완료"
                viewState.successMessage = "주문번호 \(createdOrder.orderCode)가 생성됐어요. 장바구니를 비웠고, 주문 내역 화면으로 이어질 수 있어요."
            }
        } catch let error as CheckoutFeatureError {
            apply(featureError: error)
        } catch {
            setLoadingState(
                isValidatingPrice: false,
                isSubmittingOrder: false,
                title: "주문 다시 생성하기"
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
            title: "주문 다시 생성하기"
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
            viewState.errorMessage = "앱 설정을 확인해 주세요."
        }
    }

    private func handlePaymentBridge(_ result: CheckoutPaymentBridgeResult) async {
        switch result {
        case .cancelled:
            configurePendingOrderHistoryState(
                message: "결제가 취소되었어요. 주문 내역에서 상태를 확인해 주세요."
            )
        case .failed(let message):
            configurePendingOrderHistoryState(
                message: message.isEmpty
                    ? "결제를 완료하지 못했어요. 주문 내역에서 상태를 확인해 주세요."
                    : message
            )
        case .missingImpUID:
            configurePendingOrderHistoryState(
                message: "결제 완료 정보를 확인하지 못했어요. 주문 내역에서 상태를 확인해 주세요."
            )
        case .succeeded(let impUID):
            viewState.paymentBridgeContext = nil
            viewState.errorMessage = nil
            viewState.successMessage = nil
            viewState.isPrimaryEnabled = false
            viewState.canRouteToOrderHistoryFromPrimary = false
            setLoadingState(
                isValidatingPrice: false,
                isSubmittingOrder: true,
                title: "결제 확인 중..."
            )

            do {
                let receipt = try await interactor.validatePayment(impUID: impUID)
                cartStore.clear()

                viewState.isSubmittingOrder = false
                viewState.isPrimaryLoading = false
                viewState.isPrimaryEnabled = false
                viewState.completionState = .paymentValidated
                viewState.createdOrderID = receipt.orderID ?? viewState.createdOrderID
                viewState.createdOrderCode = receipt.orderCode ?? viewState.createdOrderCode
                viewState.primaryActionTitle = "결제 확인 완료"
                viewState.successMessage = "결제가 확인됐어요. 주문 상태는 승인 대기 중일 수 있으니 주문 내역에서 이어서 확인해 주세요."
            } catch let error as CheckoutFeatureError {
                applyPendingValidationState(for: error)
            } catch {
                applyPendingValidationState(
                    message: "결제 확인이 지연되고 있어요. 주문 내역에서 상태를 확인해 주세요."
                )
            }
        }
    }

    private func setLoadingState(
        isValidatingPrice: Bool,
        isSubmittingOrder: Bool,
        title: String
    ) {
        viewState.isValidatingPrice = isValidatingPrice
        viewState.isSubmittingOrder = isSubmittingOrder
        viewState.isPrimaryLoading = isValidatingPrice || isSubmittingOrder
        viewState.primaryActionTitle = title
    }

    private func makePaymentBridgeContext(from createdOrder: CreatedOrder) -> CheckoutPaymentBridgeContext? {
        guard let payload = createdOrder.paymentBridgePayload else {
            return nil
        }

        guard let initialURL = payload.paymentURL ?? payload.redirectURL else {
            return nil
        }

        return CheckoutPaymentBridgeContext(
            orderID: createdOrder.id,
            orderCode: createdOrder.orderCode,
            initialURL: initialURL,
            redirectURL: payload.redirectURL
        )
    }

    private func configurePendingOrderHistoryState(message: String) {
        viewState.paymentBridgeContext = nil
        viewState.isValidatingPrice = false
        viewState.isSubmittingOrder = false
        viewState.isPrimaryLoading = false
        viewState.isPrimaryEnabled = viewState.createdOrderID != nil
        viewState.canRouteToOrderHistoryFromPrimary = viewState.createdOrderID != nil
        viewState.primaryActionTitle = "주문 내역 보기"
        viewState.errorMessage = message
        viewState.successMessage = nil
    }

    private func applyPendingValidationState(for error: CheckoutFeatureError) {
        let message: String

        switch error {
        case .authenticationRequired:
            message = "결제는 완료됐지만 세션이 만료되어 서버 확인이 지연되고 있어요. 다시 로그인 후 주문 내역을 확인해 주세요."
            router.routeToAuth()
        case .configurationRequired:
            message = "결제는 완료됐지만 앱 설정 문제로 서버 확인이 지연되고 있어요. 주문 내역에서 상태를 확인해 주세요."
        case .validation(let featureMessage),
             .businessAuthorization(let featureMessage),
             .notFound(let featureMessage),
             .unavailable(let featureMessage):
            message = "결제는 완료됐지만 서버 확인이 아직 끝나지 않았어요. 주문 내역에서 상태를 확인해 주세요. \(featureMessage)"
        case .validationIssues:
            message = "결제는 완료됐지만 주문 검증 이슈가 남아 있어요. 주문 내역에서 상태를 확인해 주세요."
        }

        applyPendingValidationState(message: message)
    }

    private func applyPendingValidationState(message: String) {
        cartStore.clear()
        viewState.paymentBridgeContext = nil
        viewState.isValidatingPrice = false
        viewState.isSubmittingOrder = false
        viewState.isPrimaryLoading = false
        viewState.isPrimaryEnabled = false
        viewState.canRouteToOrderHistoryFromPrimary = false
        viewState.completionState = .validationPending
        viewState.primaryActionTitle = "결제 확인 지연"
        viewState.errorMessage = nil
        viewState.successMessage = message
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
