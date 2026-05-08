import Foundation

@MainActor
protocol ProfileInteracting {
    func loadInitialState() async -> ProfileViewState
    func fetchMyProfile() async throws -> UserProfile
    func updateProfile(
        nick: String,
        phoneNumber: String?
    ) async throws -> UserProfile
    func uploadProfileImage(data: Data, fileName: String, mimeType: String) async throws -> String
    func logout() async throws
}

@MainActor
struct ProfileInteractor: ProfileInteracting {
    private let sessionStore: SessionStore
    private let authRepository: AuthRepository

    init(
        sessionStore: SessionStore,
        authRepository: AuthRepository
    ) {
        self.sessionStore = sessionStore
        self.authRepository = authRepository
    }

    func loadInitialState() async -> ProfileViewState {
        guard sessionStore.isAuthenticated else {
            return makeViewState(from: nil)
        }

        do {
            let profile = try await authRepository.fetchMyProfile()
            sessionStore.updateProfile(
                nick: profile.nick,
                profileImagePath: profile.profileImagePath
            )
            return makeViewState(from: profile)
        } catch let error as NetworkError where error.isAuthenticationFailure {
            Logger.shared.warning("Profile fetch failed: authentication required")
            await sessionStore.clearSession()
            return makeViewState(from: nil)
        } catch {
            Logger.shared.warning("Profile fetch failed: \(error.localizedDescription)")
            return makeViewState(from: nil)
        }
    }

    func fetchMyProfile() async throws -> UserProfile {
        try await authRepository.fetchMyProfile()
    }

    func updateProfile(
        nick: String,
        phoneNumber: String?
    ) async throws -> UserProfile {
        try validateNick(nick)

        return try await authRepository.updateMyProfile(
            nick: nick.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    func uploadProfileImage(data: Data, fileName: String, mimeType: String) async throws -> String {
        try await authRepository.uploadProfileImage(
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func logout() async throws {
        try await authRepository.logout()
    }

    private func makeViewState(from profile: UserProfile?) -> ProfileViewState {
        let effectiveProfile = profile ?? UserProfile(
            userID: sessionStore.currentUserID ?? "guest",
            email: sessionStore.currentSession?.email ?? "로그인 정보 없음",
            nick: sessionStore.currentSession?.displayName ?? "로그인 필요",
            phoneNumber: nil,
            profileImagePath: sessionStore.profileImagePath
        )

        return ProfileViewState(
            displayName: effectiveProfile.nick,
            email: effectiveProfile.email,
            phoneNumber: effectiveProfile.phoneNumber ?? "",
            profileImagePath: effectiveProfile.profileImagePath,
            likedStoresActionTitle: "찜한 가게 보기",
            myPostsActionTitle: "내 글 보기",
            likedPostsActionTitle: "좋아요한 글 보기",
            myReviewsActionTitle: "내 리뷰 보기",
            editProfileActionTitle: "프로필 수정",
            logoutActionTitle: sessionStore.isAuthenticated ? "로그아웃" : "로그인 필요",
            editorNick: effectiveProfile.nick,
            editorPhoneNumber: effectiveProfile.phoneNumber ?? "",
            editorProfileImagePath: effectiveProfile.profileImagePath
        )
    }

    private func validateNick(_ nick: String) throws {
        let trimmed = nick.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbiddenCharacters = CharacterSet(charactersIn: "-.,?*@+^${}()|[]\\")

        guard !trimmed.isEmpty else {
            throw AuthInputValidationError.validation(message: "닉네임을 입력해 주세요.")
        }

        guard trimmed.rangeOfCharacter(from: forbiddenCharacters) == nil else {
            throw AuthInputValidationError.validation(message: "닉네임에 사용할 수 없는 문자가 포함되어 있어요.")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
