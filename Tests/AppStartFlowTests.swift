import XCTest
@testable import Pikko

@MainActor
final class AppStartFlowTests: XCTestCase {
    func testUnauthenticatedSessionStartsFromAuthGate() {
        let appState = makeAppState()

        XCTAssertTrue(appState.shouldPresentAuthGate)
        XCTAssertEqual(appState.selectedTab, .home)
    }

    func testAuthenticatedSessionBypassesAuthGate() {
        let appState = makeAppState()

        appState.sessionStore.apply(
            session: UserSession(
                userID: "user-1",
                email: "user-1@example.com",
                displayName: "테스트 사용자",
                profileImagePath: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )

        XCTAssertFalse(appState.shouldPresentAuthGate)
    }

    func testSessionRestorerAppliesStoredSessionWhenAvailable() async {
        let appState = makeAppState()
        let sessionRestorer = SessionRestorer(
            authRepository: StubSessionRestoreAuthRepository(
                restoreResult: .success(
                    UserSession(
                        userID: "restored-user",
                        email: "restored@example.com",
                        displayName: "복원 사용자",
                        profileImagePath: nil,
                        accessToken: "restored-access",
                        refreshToken: "restored-refresh"
                    )
                )
            ),
            sessionStore: appState.sessionStore
        )

        await sessionRestorer.restoreIfAvailable()

        XCTAssertTrue(appState.sessionStore.isAuthenticated)
        XCTAssertEqual(appState.sessionStore.currentUserID, "restored-user")
    }

    func testSessionRestorerFailureClearsSessionAndReturnsToAuthGate() async {
        let appState = makeAppState()
        appState.sessionStore.apply(
            session: UserSession(
                userID: "existing-user",
                email: "existing@example.com",
                displayName: "기존 사용자",
                profileImagePath: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )
        let sessionRestorer = SessionRestorer(
            authRepository: StubSessionRestoreAuthRepository(
                restoreResult: .failure(NetworkError.unauthorized)
            ),
            sessionStore: appState.sessionStore
        )

        await sessionRestorer.restoreIfAvailable()

        XCTAssertFalse(appState.sessionStore.isAuthenticated)
        XCTAssertTrue(appState.shouldPresentAuthGate)
    }

    func testSessionRestorerNilSessionClearsExistingSessionAndReturnsToAuthGate() async {
        let appState = makeAppState()
        appState.sessionStore.apply(
            session: UserSession(
                userID: "existing-user",
                email: "existing@example.com",
                displayName: "기존 사용자",
                profileImagePath: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )
        let sessionRestorer = SessionRestorer(
            authRepository: StubSessionRestoreAuthRepository(
                restoreResult: .success(nil)
            ),
            sessionStore: appState.sessionStore
        )

        await sessionRestorer.restoreIfAvailable()

        XCTAssertFalse(appState.sessionStore.isAuthenticated)
        XCTAssertTrue(appState.shouldPresentAuthGate)
    }

    func testForbiddenSessionRestoreFailureClearsSessionAndReturnsToAuthGate() async {
        let appState = makeAppState()
        appState.sessionStore.apply(
            session: UserSession(
                userID: "existing-user",
                email: "existing@example.com",
                displayName: "기존 사용자",
                profileImagePath: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )
        let sessionRestorer = SessionRestorer(
            authRepository: StubSessionRestoreAuthRepository(
                restoreResult: .failure(NetworkError.forbidden)
            ),
            sessionStore: appState.sessionStore
        )

        await sessionRestorer.restoreIfAvailable()

        XCTAssertFalse(appState.sessionStore.isAuthenticated)
        XCTAssertTrue(appState.shouldPresentAuthGate)
    }

    func testFeatureBuilderFactorySyncsDeviceTokenWithoutBreakingAuthenticatedSession() async {
        let spyRepository = DeviceTokenSpyAuthRepository(updateDeviceTokenResult: .success(()))
        let container = makeContainer(authRepository: spyRepository)
        let appState = container.makeAppState()
        appState.sessionStore.apply(
            session: UserSession(
                userID: "user-1",
                email: "user-1@example.com",
                displayName: "테스트 사용자",
                profileImagePath: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )
        appState.sessionStore.updateDeviceToken("device-token-1")
        let featureBuilderFactory = container.makeFeatureBuilderFactory(appState: appState)

        await featureBuilderFactory.syncCurrentDeviceTokenIfNeeded()
        await featureBuilderFactory.syncCurrentDeviceTokenIfNeeded()

        let syncedTokens = await spyRepository.syncedTokens()
        XCTAssertEqual(syncedTokens, ["device-token-1"])
        XCTAssertTrue(appState.sessionStore.isAuthenticated)
        XCTAssertTrue(appState.sessionStore.hasSyncedCurrentDeviceToken)
    }

    func testFeatureBuilderFactoryIgnoresDeviceTokenSyncFailure() async {
        let spyRepository = DeviceTokenSpyAuthRepository(updateDeviceTokenResult: .failure(NetworkError.transport))
        let container = makeContainer(authRepository: spyRepository)
        let appState = container.makeAppState()
        appState.sessionStore.apply(
            session: UserSession(
                userID: "user-1",
                email: "user-1@example.com",
                displayName: "테스트 사용자",
                profileImagePath: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )
        appState.sessionStore.updateDeviceToken("device-token-1")
        let featureBuilderFactory = container.makeFeatureBuilderFactory(appState: appState)

        await featureBuilderFactory.syncCurrentDeviceTokenIfNeeded()

        let syncedTokens = await spyRepository.syncedTokens()
        XCTAssertEqual(syncedTokens, ["device-token-1"])
        XCTAssertTrue(appState.sessionStore.isAuthenticated)
        XCTAssertFalse(appState.sessionStore.hasSyncedCurrentDeviceToken)
    }

    private func makeAppState() -> AppState {
        AppState(
            sessionStore: SessionStore(
                tokenStore: StubSessionTokenStore(),
                userDefaultsStore: UserDefaultsStore(userDefaults: UserDefaults(suiteName: #function + UUID().uuidString)!)
            ),
            cartStore: CartStore(cartRepository: InMemoryCartRepository())
        )
    }

    private func makeContainer(authRepository: AuthRepository) -> AppDIContainer {
        let userDefaultsStore = UserDefaultsStore(userDefaults: UserDefaults(suiteName: #function + UUID().uuidString)!)
        return AppDIContainer(
            appConfiguration: AppConfiguration(
                environment: .development,
                baseURL: URL(string: "https://example.com")!,
                seSACKey: "test-sesac-key"
            ),
            tokenStore: StubSessionTokenStore(),
            userDefaultsStore: userDefaultsStore,
            authRepository: authRepository
        )
    }
}

private actor StubSessionTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? {
        nil
    }

    func saveTokens(_ tokens: StoredTokens) async throws {}

    func clearTokens() async throws {}
}

private struct StubSessionRestoreAuthRepository: AuthRepository {
    let restoreResult: Result<UserSession?, Error>

    func restoreSession() async throws -> UserSession? {
        try restoreResult.get()
    }

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> UserSession {
        _ = credential
        _ = deviceToken
        throw NetworkError.invalidRequest
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession {
        _ = email
        _ = password
        _ = deviceToken
        throw NetworkError.invalidRequest
    }

    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> UserSession {
        _ = email
        _ = password
        _ = nick
        _ = phoneNumber
        _ = deviceToken
        throw NetworkError.invalidRequest
    }

    func validateEmailAvailability(email: String) async throws {
        _ = email
        throw NetworkError.invalidRequest
    }

    func fetchMyProfile() async throws -> UserProfile {
        throw NetworkError.invalidRequest
    }

    func updateMyProfile(
        nick: String,
        phoneNumber: String?
    ) async throws -> UserProfile {
        _ = nick
        _ = phoneNumber
        throw NetworkError.invalidRequest
    }

    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        _ = data
        _ = fileName
        _ = mimeType
        throw NetworkError.invalidRequest
    }

    func updateDeviceToken(_ deviceToken: String) async throws {
        _ = deviceToken
        throw NetworkError.invalidRequest
    }

    func searchUsers(nick: String?) async throws -> [SearchUser] {
        _ = nick
        throw NetworkError.invalidRequest
    }

    func logout() async throws {}

    func signInStub() async throws -> UserSession {
        throw NetworkError.invalidRequest
    }
}

private actor DeviceTokenSpyAuthRepository: AuthRepository {
    private let updateDeviceTokenResult: Result<Void, Error>
    private var recordedDeviceTokens: [String] = []

    init(updateDeviceTokenResult: Result<Void, Error>) {
        self.updateDeviceTokenResult = updateDeviceTokenResult
    }

    func restoreSession() async throws -> UserSession? {
        nil
    }

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> UserSession {
        _ = credential
        _ = deviceToken
        throw NetworkError.invalidRequest
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession {
        _ = email
        _ = password
        _ = deviceToken
        throw NetworkError.invalidRequest
    }

    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> UserSession {
        _ = email
        _ = password
        _ = nick
        _ = phoneNumber
        _ = deviceToken
        throw NetworkError.invalidRequest
    }

    func validateEmailAvailability(email: String) async throws {
        _ = email
        throw NetworkError.invalidRequest
    }

    func fetchMyProfile() async throws -> UserProfile {
        throw NetworkError.invalidRequest
    }

    func updateMyProfile(
        nick: String,
        phoneNumber: String?
    ) async throws -> UserProfile {
        _ = nick
        _ = phoneNumber
        throw NetworkError.invalidRequest
    }

    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        _ = data
        _ = fileName
        _ = mimeType
        throw NetworkError.invalidRequest
    }

    func updateDeviceToken(_ deviceToken: String) async throws {
        recordedDeviceTokens.append(deviceToken)
        try updateDeviceTokenResult.get()
    }

    func searchUsers(nick: String?) async throws -> [SearchUser] {
        _ = nick
        throw NetworkError.invalidRequest
    }

    func logout() async throws {}

    func signInStub() async throws -> UserSession {
        throw NetworkError.invalidRequest
    }

    func syncedTokens() -> [String] {
        recordedDeviceTokens
    }
}
