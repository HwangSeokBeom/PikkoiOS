import Foundation

@MainActor
protocol CheckoutRouting: AnyObject {
    func routeToOrderHistory(orderID: String?)
    func routeToAuth()
    func dismissAuth()
    func clearPendingRoute()
}

@MainActor
final class CheckoutRouter: ObservableObject, CheckoutRouting {
    @Published private(set) var pendingRoute: AppRoute?
    @Published private(set) var isAuthPresented = false
    private let onOrderHistoryRoute: ((String?) -> Void)?

    init(onOrderHistoryRoute: ((String?) -> Void)? = nil) {
        self.onOrderHistoryRoute = onOrderHistoryRoute
    }

    func routeToOrderHistory(orderID: String?) {
        onOrderHistoryRoute?(orderID)
        pendingRoute = .orderHistory(orderID: orderID)
    }

    func routeToAuth() {
        isAuthPresented = true
    }

    func dismissAuth() {
        isAuthPresented = false
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}
