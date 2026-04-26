import Foundation

@MainActor
protocol OrderRouting: AnyObject {
    func routeToPrimaryDestination()
}

@MainActor
final class OrderRouter: ObservableObject, OrderRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        pendingRoute = .orderHistory(orderID: nil)
        Logger.shared.debug("TODO: Route to order detail once order IDs and destination registration exist.")
    }
}
