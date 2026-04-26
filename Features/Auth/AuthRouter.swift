import Foundation

@MainActor
protocol AuthRouting: AnyObject {
    func completeAuthentication()
}

@MainActor
final class AuthRouter: AuthRouting {
    private let onAuthenticated: () -> Void

    init(onAuthenticated: @escaping () -> Void = {}) {
        self.onAuthenticated = onAuthenticated
    }

    func completeAuthentication() {
        onAuthenticated()
    }
}
