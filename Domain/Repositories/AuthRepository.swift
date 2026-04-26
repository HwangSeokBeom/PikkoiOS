import Foundation

protocol AuthRepository: Sendable {
    func restoreSession() async throws -> UserSession?
    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> UserSession
    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession
    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> UserSession
    func validateEmailAvailability(email: String) async throws
    func fetchMyProfile() async throws -> UserProfile
    func updateMyProfile(
        nick: String,
        phoneNumber: String?,
        profileImagePath: String?
    ) async throws -> UserProfile
    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String
    func updateDeviceToken(_ deviceToken: String) async throws
    // TODO: Connect /v1/users/search to a dedicated UI when the user-search surface is defined.
    func searchUsers(nick: String?) async throws -> [SearchUser]
    func logout() async throws
    func signInStub() async throws -> UserSession
}
