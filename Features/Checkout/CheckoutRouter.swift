import Foundation

@MainActor
protocol CheckoutRouting: AnyObject {
    func routeToPrimaryDestination()
}

@MainActor
final class CheckoutRouter: ObservableObject, CheckoutRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        pendingRoute = .orderHistory
        Logger.shared.debug("TODO: Replace with post-checkout order success routing.")
    }
}
