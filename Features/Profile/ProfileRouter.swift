import Foundation

@MainActor
protocol ProfileRouting: AnyObject {
    func routeToPrimaryDestination()
}

@MainActor
final class ProfileRouter: ObservableObject, ProfileRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        pendingRoute = .orderHistory
        Logger.shared.debug("TODO: Attach ProfileRouter to order-history navigation destination.")
    }
}
