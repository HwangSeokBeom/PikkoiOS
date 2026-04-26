import Foundation

@MainActor
protocol StoreDetailRouting: AnyObject {
    func routeToPrimaryDestination()
}

@MainActor
final class StoreDetailRouter: ObservableObject, StoreDetailRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        pendingRoute = .cart
        Logger.shared.debug("TODO: Present cart from StoreDetailRouter after add-to-cart wiring exists.")
    }
}
