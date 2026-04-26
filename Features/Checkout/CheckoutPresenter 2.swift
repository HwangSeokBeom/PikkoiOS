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
        case .primaryButtonTapped:
            await submitOrder()
        case .orderHistoryTapped:
            guard let createdOrderID = viewState.createdOrderID else { return }
            router.routeToOrderHistory(orderID: createdOrderID)
        }
    }

    private func submitOrder() async {
        guard viewState.isPrimaryEnabled, !viewState.isPrimaryLoading else { return }

        viewState.isPrimaryLoading = true
        viewState.errorMessage = nil
        viewState.successMessage = nil
        viewState.primaryActionTitle = "주문 생성 중..."

        do {
            let createdOrder = try await interactor.submitOrder()
            cartStore.clear()
            viewState.isPrimaryLoading = false
            viewState.isPrimaryEnabled = false
            viewState.createdOrderID = createdOrder.id
            viewState.createdOrderCode = createdOrder.orderCode
            viewState.totalPriceText = formatWon(createdOrder.totalPriceAmount)
            viewState.primaryActionTitle = "주문 생성 완료"
            viewState.successMessage = "주문번호 \(createdOrder.orderCode)가 생성됐어요. 장바구니는 비웠고, 다음 단계에서 주문 내역으로 이어집니다."
        } catch let error as CheckoutFeatureError {
            viewState.isPrimaryLoading = false
            viewState.isPrimaryEnabled = !viewState.isEmpty
            viewState.primaryActionTitle = "주문 다시 생성하기"
            viewState.errorMessage = message(for: error)
        } catch {
            viewState.isPrimaryLoading = false
            viewState.isPrimaryEnabled = !viewState.isEmpty
            viewState.primaryActionTitle = "주문 다시 생성하기"
            viewState.errorMessage = "주문 생성 중 알 수 없는 오류가 발생했어요."
        }
    }

    private func message(for error: CheckoutFeatureError) -> String {
        switch error {
        case .validation(let message),
             .businessAuthorization(let message),
             .notFound(let message),
             .unavailable(let message):
            return message
        case .authenticationRequired:
            return "로그인 후 주문을 생성할 수 있어요."
        case .configurationRequired:
            return "SeSACKey 설정을 확인해 주세요."
        }
    }

    private func formatWon(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ko_KR")
        return "\(formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")원"
    }
}
