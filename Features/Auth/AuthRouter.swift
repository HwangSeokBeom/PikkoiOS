import Foundation

@MainActor
protocol AuthRouting: AnyObject {
    func routeToPostAuthHome()
}

@MainActor
final class AuthRouter: ObservableObject, AuthRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPostAuthHome() {
        pendingRoute = .home
    }
}
