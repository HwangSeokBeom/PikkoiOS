import Foundation

@MainActor
protocol CartRouting: AnyObject {
    func routeToPrimaryDestination()
    func clearPendingRoute()
}

@MainActor
final class CartRouter: ObservableObject, CartRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        pendingRoute = .checkout
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}
