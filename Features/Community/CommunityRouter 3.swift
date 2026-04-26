import Foundation

@MainActor
protocol CommunityRouting: AnyObject {
    func routeToPrimaryDestination()
}

@MainActor
final class CommunityRouter: ObservableObject, CommunityRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPrimaryDestination() {
        pendingRoute = .community
        Logger.shared.debug("TODO: Push community thread/detail destinations.")
    }
}
