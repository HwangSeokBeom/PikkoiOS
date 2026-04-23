import Foundation

struct UserSession: Equatable, Sendable {
    let userID: String
    let displayName: String
    let profileImagePath: String?
    let accessToken: String
    let refreshToken: String

    var authToken: String {
        accessToken
    }

    var nick: String {
        displayName
    }

    func updatingTokens(accessToken: String, refreshToken: String) -> UserSession {
        UserSession(
            userID: userID,
            displayName: displayName,
            profileImagePath: profileImagePath,
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }
}
