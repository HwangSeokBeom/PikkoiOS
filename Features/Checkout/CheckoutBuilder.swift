import Foundation
import SwiftUI

@MainActor
struct CheckoutBuilder {
    private let draft: CheckoutDraft
    private let orderRepository: OrderRepository
    private let cartStore: CartStore
    private let makeAuthView: () -> AnyView
    private let makeOrderView: (String?) -> OrderRootView
    private let makePaymentBridgeView: (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView
    private let onOrderHistoryRoute: (String?) -> Void

    init(
        draft: CheckoutDraft,
        orderRepository: OrderRepository,
        cartStore: CartStore,
        makeAuthView: @escaping () -> AnyView,
        makeOrderView: @escaping (String?) -> OrderRootView,
        makePaymentBridgeView: @escaping (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView,
        onOrderHistoryRoute: @escaping (String?) -> Void = { _ in }
    ) {
        self.draft = draft
        self.orderRepository = orderRepository
        self.cartStore = cartStore
        self.makeAuthView = makeAuthView
        self.makeOrderView = makeOrderView
        self.makePaymentBridgeView = makePaymentBridgeView
        self.onOrderHistoryRoute = onOrderHistoryRoute
    }

    func build() -> CheckoutRootView {
        let router = CheckoutRouter(onOrderHistoryRoute: onOrderHistoryRoute)
        let interactor = CheckoutInteractor(
            draft: draft,
            orderRepository: orderRepository
        )
        let presenter = CheckoutPresenter(
            interactor: interactor,
            router: router,
            cartStore: cartStore
        )
        return CheckoutRootView(
            presenter: presenter,
            router: router,
            makeAuthView: makeAuthView,
            makeOrderView: makeOrderView,
            makePaymentBridgeView: makePaymentBridgeView
        )
    }
}
