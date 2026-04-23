import Foundation

struct InMemoryAuthRepository: AuthRepository {
    func restoreSession() async throws -> UserSession? {
        // TODO: Replace with persisted credential/session restoration.
        nil
    }

    func signInStub() async throws -> UserSession {
        UserSession(
            userID: "stub-user",
            displayName: "Pikko Guest",
            profileImagePath: nil,
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token"
        )
    }
}
