import Foundation

@MainActor
protocol ChatRouting: AnyObject {
    func routeToPrimaryDestination()
}

@MainActor
final class ChatRouter: ObservableObject, ChatRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        Logger.shared.debug("TODO: Push chat room destinations once room models exist.")
    }
}
