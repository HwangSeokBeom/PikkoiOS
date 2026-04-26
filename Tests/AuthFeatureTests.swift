import XCTest
@testable import Pikko

@MainActor
final class AuthFeatureTests: XCTestCase {
    func testAuthInteractorHidesStubSignInWhenDisabled() async {
        let appConfiguration = makeAppConfiguration()
        let interactor = AuthInteractor(
            authRepository: InMemoryAuthRepository(),
            socialAuthService: StubSocialAuthService(),
            appConfiguration: appConfiguration,
            allowsStubSignIn: false
        )

        let state = await interactor.loadInitialState()

        XCTAssertFalse(state.showsStubSignIn)
    }

    func testAuthInteractorShowsProviderButtonsAndStubWhenEnabled() async {
        let appConfiguration = makeAppConfiguration()
        let interactor = AuthInteractor(
            authRepository: InMemoryAuthRepository(),
            socialAuthService: StubSocialAuthService(),
            appConfiguration: appConfiguration,
            allowsStubSignIn: true
        )

        let state = await interactor.loadInitialState()

        XCTAssertTrue(state.showsStubSignIn)
        XCTAssertEqual(state.providerButtons.map(\.provider), [.kakao, .apple])
    }

    func testAuthInteractorShowsConfigurationMessageWithoutDisablingProvidersWhenBaseURLIsInvalid() async {
        let appConfiguration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "v1")!,
            seSACKey: "test-sesac-key",
            kakaoNativeAppKey: "kakao-key",
            googleIOSClientID: "google-client-id",
            googleReversedClientID: "google-reversed-id"
        )
        let interactor = AuthInteractor(
            authRepository: InMemoryAuthRepository(),
            socialAuthService: SocialAuthService(appConfiguration: appConfiguration),
            appConfiguration: appConfiguration
        )

        let state = await interactor.loadInitialState()

        XCTAssertTrue(state.providerButtons.allSatisfy { $0.isEnabled })
        XCTAssertEqual(state.providerButtons.map(\.provider), [.kakao, .apple])
        XCTAssertEqual(
            state.configurationMessage,
            "PIKKO_BASE_URL이 올바르지 않습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
        )
    }

    func testAuthPresenterProviderTapPersistsSessionAndCompletesRouting() async {
        let sessionStore = makeSessionStore()
        let router = SpyAuthRouter()
        let repository = SpyAuthRepository()
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: repository,
                socialAuthService: StubSocialAuthService(
                    signInResult: .success(
                        SocialLoginCredential(
                            provider: .kakao,
                            accessToken: "provider-access",
                            idToken: nil,
                            authorizationCode: nil,
                            email: "pikko@example.com",
                            nickname: "픽코",
                            rawNonce: nil,
                            userIdentifier: "provider-user"
                        )
                    )
                ),
                appConfiguration: makeAppConfiguration()
            ),
            router: router,
            sessionStore: sessionStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.providerTapped(.kakao))

        let recordedCredential = await repository.recordedCredential
        XCTAssertEqual(recordedCredential?.provider, .kakao)
        XCTAssertTrue(sessionStore.isAuthenticated)
        XCTAssertEqual(sessionStore.currentUserID, "server-user")
        XCTAssertEqual(router.completeAuthenticationCount, 1)
    }

    func testAuthViewStateDoesNotExposeGoogleProvider() {
        XCTAssertEqual(AuthProvider.visibleProviders, [.kakao, .apple])
    }

    func testAuthPresenterSilentlyHandlesCancelledSocialSignIn() async {
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: SpyAuthRepository(),
                socialAuthService: StubSocialAuthService(
                    signInResult: .failure(SocialAuthError.cancelled(provider: .kakao))
                ),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.providerTapped(.kakao))

        XCTAssertNil(presenter.viewState.errorMessage)
        XCTAssertFalse(presenter.viewState.isLoading)
        XCTAssertNil(presenter.viewState.loadingProvider)
    }

    func testAuthPresenterSuppressesDuplicateConfigurationErrorCard() async {
        let appConfiguration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "v1")!,
            seSACKey: "test-sesac-key"
        )
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: FailingAuthRepository(error: NetworkError.configuration(.invalidBaseURL)),
                socialAuthService: StubSocialAuthService(),
                appConfiguration: appConfiguration
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.providerTapped(.kakao))

        XCTAssertEqual(
            presenter.viewState.configurationMessage,
            "PIKKO_BASE_URL이 올바르지 않습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
        )
        XCTAssertNil(presenter.viewState.errorMessage)
    }

    func testAuthPresenterEmailSignInPersistsSessionAndCompletesRouting() async {
        let sessionStore = makeSessionStore()
        let router = SpyAuthRouter()
        let repository = SpyAuthRepository()
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: repository,
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: router,
            sessionStore: sessionStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("pikko@example.com"))
        await presenter.send(.passwordChanged("Password1!"))
        await presenter.send(.emailSignInTapped)

        let recordedEmailSignIn = await repository.recordedEmailSignIn
        XCTAssertEqual(recordedEmailSignIn?.email, "pikko@example.com")
        XCTAssertTrue(sessionStore.isAuthenticated)
        XCTAssertEqual(sessionStore.email, "server@example.com")
        XCTAssertEqual(router.completeAuthenticationCount, 1)
    }

    func testAuthPresenterEmailSignUpValidatesNick() async {
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: SpyAuthRepository(),
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("pikko@example.com"))
        await presenter.send(.passwordChanged("Password1!"))
        await presenter.send(.passwordConfirmationChanged("Password1!"))
        await presenter.send(.validateEmailTapped)
        await presenter.send(.nickChanged("bad-nick"))
        await presenter.send(.signUpTapped)

        XCTAssertEqual(presenter.viewState.errorMessage, "닉네임에 사용할 수 없는 문자가 포함되어 있어요.")
        XCTAssertFalse(presenter.viewState.isLoading)
    }

    func testAuthPresenterSignUpRequiresMatchingPasswordConfirmation() async {
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: SpyAuthRepository(),
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("pikko@example.com"))
        await presenter.send(.passwordChanged("Password1!"))
        await presenter.send(.passwordConfirmationChanged("Password2!"))
        await presenter.send(.nickChanged("픽코"))
        await presenter.send(.signUpTapped)

        XCTAssertEqual(presenter.viewState.errorMessage, "비밀번호 확인이 일치하지 않아요.")
        XCTAssertFalse(presenter.viewState.isLoading)
    }

    func testAuthPresenterMarksEmailAsAvailableWhenValidationSucceeds() async {
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: SpyAuthRepository(),
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("pikko@example.com"))
        await presenter.send(.passwordChanged("Password1!"))
        await presenter.send(.passwordConfirmationChanged("Password1!"))
        await presenter.send(.nickChanged("픽코"))
        await presenter.send(.validateEmailTapped)

        XCTAssertEqual(
            presenter.viewState.emailValidationState,
            .available(message: "사용 가능한 이메일이에요.")
        )
        XCTAssertTrue(presenter.viewState.canSubmitSignUp)
    }

    func testAuthPresenterMarksEmailAsUnavailableWhenValidationConflicts() async {
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: SpyAuthRepository(
                    validateEmailResult: .failure(NetworkError.conflict(message: "이미 사용 중인 이메일이에요."))
                ),
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("used@example.com"))
        await presenter.send(.validateEmailTapped)

        XCTAssertEqual(
            presenter.viewState.emailValidationState,
            .unavailable(message: "이미 사용 중인 이메일이에요.")
        )
        XCTAssertFalse(presenter.viewState.canSubmitSignUp)
    }

    func testAuthPresenterMarksEmailAsInvalidWhenValidationReturnsBadRequest() async {
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: SpyAuthRepository(
                    validateEmailResult: .failure(NetworkError.invalidRequest)
                ),
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("pikko@example.com"))
        await presenter.send(.validateEmailTapped)

        XCTAssertEqual(
            presenter.viewState.emailValidationState,
            .unavailable(message: "이메일 형식을 다시 확인해 주세요.")
        )
        XCTAssertFalse(presenter.viewState.canSubmitSignUp)
    }

    func testAuthPresenterResetsEmailValidationStateWhenEmailChanges() async {
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: SpyAuthRepository(
                    validateEmailResult: .failure(NetworkError.conflict(message: "이미 사용 중인 이메일이에요."))
                ),
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("used@example.com"))
        await presenter.send(.validateEmailTapped)

        XCTAssertEqual(
            presenter.viewState.emailValidationState,
            .unavailable(message: "이미 사용 중인 이메일이에요.")
        )

        await presenter.send(.emailChanged("new@example.com"))

        XCTAssertEqual(presenter.viewState.emailValidationState, .idle)
    }

    func testAuthPresenterRequiresServerEmailValidationBeforeSignUp() async {
        let repository = SpyAuthRepository()
        let presenter = AuthPresenter(
            interactor: AuthInteractor(
                authRepository: repository,
                socialAuthService: StubSocialAuthService(),
                appConfiguration: makeAppConfiguration()
            ),
            router: SpyAuthRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.emailChanged("pikko@example.com"))
        await presenter.send(.passwordChanged("Password1!"))
        await presenter.send(.passwordConfirmationChanged("Password1!"))
        await presenter.send(.nickChanged("픽코"))
        await presenter.send(.signUpTapped)

        let signUpCalls = await repository.signUpCallCount()
        XCTAssertEqual(presenter.viewState.errorMessage, "이메일 중복 확인을 완료해 주세요.")
        XCTAssertEqual(signUpCalls, 0)
    }

    func testUserInfoListResponseDTODecodesSearchUsers() throws {
        let data = """
        {
          "data": [
            {
              "user_id": "user-1",
              "nick": "픽코유저",
              "profileImage": "/data/profiles/pikko.jpg"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try NetworkCoding.makeJSONDecoder().decode(UserInfoListResponseDTO.self, from: data)

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.userID, "user-1")
        XCTAssertEqual(response.data.first?.nick, "픽코유저")
    }

    private func makeSessionStore() -> SessionStore {
        SessionStore(
            tokenStore: StubAuthTokenStore(),
            userDefaultsStore: UserDefaultsStore(userDefaults: UserDefaults(suiteName: #function + UUID().uuidString)!)
        )
    }

    private func makeAppConfiguration() -> AppConfiguration {
        AppConfiguration(
            environment: .development,
            baseURL: URL(string: "https://example.com")!,
            seSACKey: "test-sesac-key",
            kakaoNativeAppKey: "kakao-key",
            googleIOSClientID: "google-client-id",
            googleReversedClientID: "google-reversed-id"
        )
    }
}

@MainActor
final class ProfileFeatureTests: XCTestCase {
    func testProfilePresenterSaveUpdatesSessionAndState() async {
        let sessionStore = makeSessionStore()
        sessionStore.apply(
            session: UserSession(
                userID: "user-1",
                email: "user@example.com",
                displayName: "기존 닉네임",
                profileImagePath: nil,
                accessToken: "access",
                refreshToken: "refresh"
            )
        )

        let presenter = ProfilePresenter(
            interactor: SpyProfileInteractor(),
            router: ProfileRouter(),
            sessionStore: sessionStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.editProfileTapped)
        await presenter.send(.editorNickChanged("새 닉네임"))
        await presenter.send(.editorPhoneNumberChanged("010-1234-5678"))
        await presenter.send(.saveProfileTapped)

        XCTAssertEqual(sessionStore.nick, "새 닉네임")
        XCTAssertEqual(presenter.viewState.displayName, "새 닉네임")
        XCTAssertEqual(presenter.viewState.phoneNumber, "010-1234-5678")
        XCTAssertEqual(presenter.viewState.noticeMessage, "프로필을 저장했어요.")
        XCTAssertFalse(presenter.viewState.isEditingProfile)
    }

    func testProfilePresenterAppliesUploadedImagePathToEditor() async {
        let sessionStore = makeSessionStore()
        sessionStore.apply(
            session: UserSession(
                userID: "user-1",
                email: "user@example.com",
                displayName: "기존 닉네임",
                profileImagePath: nil,
                accessToken: "access",
                refreshToken: "refresh"
            )
        )

        let presenter = ProfilePresenter(
            interactor: SpyProfileInteractor(
                uploadedImagePath: "https://example.com/profile/uploaded.jpg"
            ),
            router: ProfileRouter(),
            sessionStore: sessionStore
        )

        await presenter.send(.onAppear)
        await presenter.send(.editProfileTapped)
        await presenter.send(.profileImageDataSelected(Data([0x01, 0x02]), fileName: "profile.jpg"))

        XCTAssertEqual(
            presenter.viewState.editorProfileImagePath,
            "https://example.com/profile/uploaded.jpg"
        )
        XCTAssertEqual(presenter.viewState.editorInfoMessage, "프로필 이미지를 업로드했어요.")
        XCTAssertNil(presenter.viewState.profileImageUploadErrorMessage)
    }

    private func makeSessionStore() -> SessionStore {
        SessionStore(
            tokenStore: StubAuthTokenStore(),
            userDefaultsStore: UserDefaultsStore(userDefaults: UserDefaults(suiteName: #function + UUID().uuidString)!)
        )
    }
}

@MainActor
private final class SpyAuthRouter: AuthRouting {
    private(set) var completeAuthenticationCount = 0

    func completeAuthentication() {
        completeAuthenticationCount += 1
    }
}

private actor SpyAuthRepository: AuthRepository {
    private(set) var recordedCredential: SocialLoginCredential?
    private(set) var recordedEmailSignIn: (email: String, password: String, deviceToken: String?)?
    private let validateEmailResult: Result<Void, Error>
    private let storedProfile: UserProfile
    private let uploadProfileImageResult: Result<String, Error>
    private var signUpCalls = 0

    init(
        validateEmailResult: Result<Void, Error> = .success(()),
        storedProfile: UserProfile = UserProfile(
            userID: "server-user",
            email: "server@example.com",
            nick: "Pikko User",
            phoneNumber: "010-0000-0000",
            profileImagePath: "https://example.com/profile/current.jpg"
        ),
        uploadProfileImageResult: Result<String, Error> = .success("https://example.com/profile/uploaded.jpg")
    ) {
        self.validateEmailResult = validateEmailResult
        self.storedProfile = storedProfile
        self.uploadProfileImageResult = uploadProfileImageResult
    }

    func restoreSession() async throws -> UserSession? {
        nil
    }

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> UserSession {
        recordedCredential = credential
        _ = deviceToken
        return UserSession(
            userID: "server-user",
            email: "server@example.com",
            displayName: "Pikko User",
            profileImagePath: nil,
            accessToken: "server-access",
            refreshToken: "server-refresh"
        )
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession {
        recordedEmailSignIn = (email, password, deviceToken)
        return UserSession(
            userID: "server-user",
            email: "server@example.com",
            displayName: "Pikko User",
            profileImagePath: nil,
            accessToken: "server-access",
            refreshToken: "server-refresh"
        )
    }

    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> UserSession {
        signUpCalls += 1
        _ = password
        _ = phoneNumber
        _ = deviceToken
        return UserSession(
            userID: "joined-user",
            email: email,
            displayName: nick,
            profileImagePath: nil,
            accessToken: "server-access",
            refreshToken: "server-refresh"
        )
    }

    func signUpCallCount() -> Int {
        signUpCalls
    }

    func validateEmailAvailability(email: String) async throws {
        _ = email
        try validateEmailResult.get()
    }

    func fetchMyProfile() async throws -> UserProfile {
        storedProfile
    }

    func updateMyProfile(
        nick: String,
        phoneNumber: String?,
        profileImagePath: String?
    ) async throws -> UserProfile {
        UserProfile(
            userID: storedProfile.userID,
            email: storedProfile.email,
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
        return try uploadProfileImageResult.get()
    }

    func updateDeviceToken(_ deviceToken: String) async throws {
        _ = deviceToken
    }

    func searchUsers(nick: String?) async throws -> [SearchUser] {
        let keyword = nick?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !keyword.isEmpty else { return [] }
        return [SearchUser(id: "search-user", nick: keyword, profileImagePath: nil)]
    }

    func logout() async throws {}

    func signInStub() async throws -> UserSession {
        UserSession(
            userID: "stub-user",
            email: nil,
            displayName: "Stub User",
            profileImagePath: nil,
            accessToken: "stub-access",
            refreshToken: "stub-refresh"
        )
    }
}

private actor FailingAuthRepository: AuthRepository {
    private let error: NetworkError

    init(error: NetworkError) {
        self.error = error
    }

    func restoreSession() async throws -> UserSession? {
        nil
    }

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> UserSession {
        _ = credential
        _ = deviceToken
        throw error
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession {
        _ = email
        _ = password
        _ = deviceToken
        throw error
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
        throw error
    }

    func validateEmailAvailability(email: String) async throws {
        _ = email
        throw error
    }

    func fetchMyProfile() async throws -> UserProfile {
        throw error
    }

    func updateMyProfile(
        nick: String,
        phoneNumber: String?,
        profileImagePath: String?
    ) async throws -> UserProfile {
        _ = nick
        _ = phoneNumber
        _ = profileImagePath
        throw error
    }

    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        _ = data
        _ = fileName
        _ = mimeType
        throw error
    }

    func updateDeviceToken(_ deviceToken: String) async throws {
        _ = deviceToken
        throw error
    }

    func searchUsers(nick: String?) async throws -> [SearchUser] {
        _ = nick
        throw error
    }

    func logout() async throws {}

    func signInStub() async throws -> UserSession {
        throw error
    }
}

@MainActor
private struct SpyProfileInteractor: ProfileInteracting {
    var initialState = ProfileViewState(
        displayName: "기존 닉네임",
        email: "user@example.com",
        phoneNumber: "",
        profileImagePath: nil,
        likedStoresActionTitle: "찜한 가게 보기",
        editProfileActionTitle: "프로필 수정",
        logoutActionTitle: "로그아웃",
        editorNick: "기존 닉네임",
        editorPhoneNumber: "",
        editorProfileImagePath: nil
    )
    var updatedProfile = UserProfile(
        userID: "user-1",
        email: "user@example.com",
        nick: "새 닉네임",
        phoneNumber: "010-1234-5678",
        profileImagePath: nil
    )
    var uploadedImagePath = "https://example.com/profile/uploaded.jpg"

    func loadInitialState() async -> ProfileViewState {
        initialState
    }

    func updateProfile(
        nick: String,
        phoneNumber: String?,
        profileImagePath: String?
    ) async throws -> UserProfile {
        UserProfile(
            userID: updatedProfile.userID,
            email: updatedProfile.email,
            nick: nick,
            phoneNumber: phoneNumber,
            profileImagePath: profileImagePath
        )
    }

    func uploadProfileImage(data: Data, fileName: String, mimeType: String) async throws -> String {
        _ = data
        _ = fileName
        _ = mimeType
        return uploadedImagePath
    }

    func logout() async throws {}
}

@MainActor
private final class StubSocialAuthService: SocialAuthProviding, @unchecked Sendable {
    private let signInResult: Result<SocialLoginCredential, Error>

    init(
        signInResult: Result<SocialLoginCredential, Error> = .success(
            SocialLoginCredential(
                provider: .apple,
                accessToken: nil,
                idToken: "id-token",
                authorizationCode: "auth-code",
                email: "pikko@example.com",
                nickname: "Pikko",
                rawNonce: "nonce",
                userIdentifier: "apple-user"
            )
        )
    ) {
        self.signInResult = signInResult
    }

    func prepareIfNeeded() {}

    func availability(for provider: AuthProvider) -> SocialAuthProviderAvailability {
        .init(provider: provider, isEnabled: true, disabledReason: nil)
    }

    func signIn(with provider: AuthProvider) async throws -> SocialLoginCredential {
        switch signInResult {
        case .success(let credential):
            return SocialLoginCredential(
                provider: provider,
                accessToken: credential.accessToken,
                idToken: credential.idToken,
                authorizationCode: credential.authorizationCode,
                email: credential.email,
                nickname: credential.nickname,
                rawNonce: credential.rawNonce,
                userIdentifier: credential.userIdentifier
            )
        case .failure(let error):
            throw error
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        false
    }
}

private actor StubAuthTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}
