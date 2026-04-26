import Foundation

enum AuthorizationPolicy: Sendable {
    case none
    case accessToken
    case refreshToken
    case fileAuthorized
}

extension AuthorizationPolicy {
    var requiresAuthenticatedSession: Bool {
        switch self {
        case .none:
            return false
        case .accessToken, .refreshToken, .fileAuthorized:
            return true
        }
    }
}
