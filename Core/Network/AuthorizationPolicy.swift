import Foundation

enum AuthorizationPolicy: Sendable {
    case none
    case accessToken
    case refreshToken
    case fileAuthorized
}
