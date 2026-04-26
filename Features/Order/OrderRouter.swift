import Foundation

@MainActor
protocol OrderRouting: AnyObject {
    func routeToOrderDetail(orderID: String)
    func routeToAuth()
    func dismissAuth()
    func routeToExploreHome()
    func clearPendingRoute()
}

@MainActor
final class OrderRouter: ObservableObject, OrderRouting {
    @Published private(set) var pendingRoute: AppRoute?
    @Published private(set) var isAuthPresented = false

    private let onExploreHome: () -> Void

    init(onExploreHome: @escaping () -> Void = {}) {
        self.onExploreHome = onExploreHome
    }

    func routeToOrderDetail(orderID: String) {
        pendingRoute = .orderDetail(orderID: orderID)
    }

    func routeToAuth() {
        isAuthPresented = true
    }

    func dismissAuth() {
        isAuthPresented = false
    }

    func routeToExploreHome() {
        onExploreHome()
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}
