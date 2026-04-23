import Foundation

extension Notification.Name {
    static let pikkoSessionDidInvalidate = Notification.Name("pikko.session.didInvalidate")
    static let pikkoTokensDidRefresh = Notification.Name("pikko.session.tokensDidRefresh")
}

enum NetworkSessionNotificationUserInfoKey {
    static let accessToken = "accessToken"
    static let refreshToken = "refreshToken"
}
