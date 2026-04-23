import Foundation

@MainActor
protocol CartRouting: AnyObject {
    func routeToPrimaryDestination()
}

@MainActor
final class CartRouter: ObservableObject, CartRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        pendingRoute = .checkout
        Logger.shared.debug("TODO: Push checkout from CartRouter once root navigation graph is wired.")
    }
}
