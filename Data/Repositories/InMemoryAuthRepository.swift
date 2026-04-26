import Foundation

struct InMemoryAuthRepository: AuthRepository {
    func restoreSession() async throws -> UserSession? {
        // TODO: Replace with persisted credential/session restoration.
        nil
    }

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> UserSession {
        _ = deviceToken
        return UserSession(
            userID: credential.userIdentifier ?? "\(credential.provider.rawValue)-user",
            email: credential.email,
            displayName: credential.nickname ?? credential.email ?? "Pikko User",
            profileImagePath: nil,
            accessToken: credential.accessToken ?? "stub-access-token",
            refreshToken: credential.idToken ?? credential.authorizationCode ?? "stub-refresh-token"
        )
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession {
        _ = password
        _ = deviceToken
        return UserSession(
            userID: "email-user",
            email: email,
            displayName: email.components(separatedBy: "@").first ?? "Pikko User",
            profileImagePath: nil,
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token"
        )
    }

    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> UserSession {
        _ = password
        _ = phoneNumber
        _ = deviceToken
        return UserSession(
            userID: "joined-user",
            email: email,
            displayName: nick,
            profileImagePath: nil,
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token"
        )
    }

    func validateEmailAvailability(email: String) async throws {
        _ = email
    }

    func fetchMyProfile() async throws -> UserProfile {
        UserProfile(
            userID: "stub-user",
            email: "stub@example.com",
            nick: "Pikko Stub User",
            phoneNumber: nil,
            profileImagePath: nil
        )
    }

    func updateMyProfile(
        nick: String,
        phoneNumber: String?,
        profileImagePath: String?
    ) async throws -> UserProfile {
        UserProfile(
            userID: "stub-user",
            email: "stub@example.com",
            nick: nick,
            phoneNumber: phoneNumber,
            profileImagePath: profileImagePath
        )
    }

    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        _ = data
        _ = fileName
        _ = mimeType
        return "https://example.com/profile/stub.jpg"
    }

    func updateDeviceToken(_ deviceToken: String) async throws {
        _ = deviceToken
    }

    func searchUsers(nick: String?) async throws -> [SearchUser] {
        let keyword = nick?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !keyword.isEmpty else { return [] }

        return [
            SearchUser(
                id: "stub-user",
                nick: keyword,
                profileImagePath: nil
            )
        ]
    }

    func logout() async throws {}

    func signInStub() async throws -> UserSession {
        return UserSession(
            userID: "stub-user",
            email: nil,
            displayName: "Pikko Stub User",
            profileImagePath: nil,
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token"
        )
    }
}
