import Foundation

struct UserSession: Equatable, Sendable {
    let userID: String
    let email: String?
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
            email: email,
            displayName: displayName,
            profileImagePath: profileImagePath,
            accessToken: accessToken,
            refreshToken: refreshToken
        )
    }
}

struct UserProfile: Equatable, Sendable {
    let userID: String
    let email: String
    let nick: String
    let phoneNumber: String?
    let profileImagePath: String?
}

struct SearchUser: Equatable, Sendable, Identifiable {
    let id: String
    let nick: String
    let profileImagePath: String?
}
