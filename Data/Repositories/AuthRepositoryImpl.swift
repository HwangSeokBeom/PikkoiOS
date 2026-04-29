import Foundation

struct AuthRepositoryImpl: AuthRepository {
    private let remoteDataSource: any AuthRemoteDataSourceProtocol
    private let tokenStore: any TokenStore
    private let sessionSnapshotStore: any SessionSnapshotStoring
    private let fileURLResolver: any AuthorizedFileURLResolving

    init(
        remoteDataSource: any AuthRemoteDataSourceProtocol,
        tokenStore: any TokenStore,
        sessionSnapshotStore: any SessionSnapshotStoring,
        fileURLResolver: any AuthorizedFileURLResolving
    ) {
        self.remoteDataSource = remoteDataSource
        self.tokenStore = tokenStore
        self.sessionSnapshotStore = sessionSnapshotStore
        self.fileURLResolver = fileURLResolver
    }

    func restoreSession() async throws -> UserSession? {
        guard let tokens = try await tokenStore.loadTokens() else {
            try? await sessionSnapshotStore.saveSnapshot(nil)
            return nil
        }

        guard let snapshot = await sessionSnapshotStore.loadSnapshot() else {
            try? await tokenStore.clearTokens()
            try? await sessionSnapshotStore.saveSnapshot(nil)
            return nil
        }

        do {
            let profile = try await fetchMyProfile()
            let latestTokens = try await tokenStore.loadTokens() ?? tokens
            return UserSession(
                userID: profile.userID,
                email: profile.email,
                displayName: profile.nick,
                profileImagePath: profile.profileImagePath,
                accessToken: latestTokens.accessToken,
                refreshToken: latestTokens.refreshToken
            )
        } catch let error as NetworkError {
            if error.isAuthenticationFailure {
                try? await tokenStore.clearTokens()
                try? await sessionSnapshotStore.saveSnapshot(nil)
                Logger.shared.warning("Session restoration cleared invalid stored credentials: \(error.localizedDescription)")
                return nil
            }

            Logger.shared.warning("Session restoration fell back to stored snapshot: \(error.localizedDescription)")
            return snapshot.makeSession(tokens: tokens)
        }
    }

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> UserSession {
        let response = try await remoteDataSource.signIn(with: credential, deviceToken: deviceToken)
        return makeSession(from: response)
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession {
        let response = try await remoteDataSource.signIn(
            email: email,
            password: password,
            deviceToken: deviceToken
        )
        return makeSession(from: response)
    }

    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> UserSession {
        let response = try await remoteDataSource.signUp(
            email: email,
            password: password,
            nick: nick,
            phoneNumber: phoneNumber,
            deviceToken: deviceToken
        )
        return makeSession(from: response)
    }

    func validateEmailAvailability(email: String) async throws {
        try await remoteDataSource.validateEmailAvailability(email: email)
    }

    func fetchMyProfile() async throws -> UserProfile {
        let response = try await remoteDataSource.fetchMyProfile()
        return mapProfile(response)
    }

    func updateMyProfile(
        nick: String,
        phoneNumber: String?,
        profileImagePath: String?
    ) async throws -> UserProfile {
        let response = try await remoteDataSource.updateMyProfile(
            nick: nick,
            phoneNumber: phoneNumber,
            profileImagePath: profileImagePath
        )
        return mapProfile(response)
    }

    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        let response = try await remoteDataSource.uploadProfileImage(
            data: data,
            fileName: fileName,
            mimeType: mimeType
        )

        guard let resolvedPath = resolveProfileImagePath(response.profileImage),
              !resolvedPath.isEmpty else {
            throw NetworkError.decoding
        }

        return resolvedPath
    }

    func updateDeviceToken(_ deviceToken: String) async throws {
        try await remoteDataSource.updateDeviceToken(deviceToken)
    }

    func searchUsers(nick: String?) async throws -> [SearchUser] {
        let response = try await remoteDataSource.searchUsers(nick: nick)
        return response.data.map { dto in
            SearchUser(
                id: dto.userID,
                nick: dto.nick,
                profileImagePath: resolveProfileImagePath(dto.profileImage)
            )
        }
    }

    func logout() async throws {
        do {
            try await remoteDataSource.logout()
        } catch let error as NetworkError where error.isAuthenticationFailure {
            return
        }
        // TODO: Add provider-specific SDK logout/revoke once Kakao/Apple sign-out policy is finalized.
    }

    func signInStub() async throws -> UserSession {
        UserSession(
            userID: "stub-user",
            email: nil,
            displayName: "Pikko Stub User",
            profileImagePath: nil,
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token"
        )
    }

    private func makeSession(from response: LoginResponseDTO) -> UserSession {
        UserSession(
            userID: response.userID,
            email: response.email,
            displayName: response.nick,
            profileImagePath: resolveProfileImagePath(response.profileImage),
            accessToken: response.accessToken,
            refreshToken: response.refreshToken
        )
    }

    private func mapProfile(_ dto: MyInfoResponseDTO) -> UserProfile {
        UserProfile(
            userID: dto.userID,
            email: dto.email,
            nick: dto.nick,
            phoneNumber: dto.phoneNum?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            profileImagePath: resolveProfileImagePath(dto.profileImage)
        )
    }

    private func resolveProfileImagePath(_ path: String?) -> String? {
        (try? fileURLResolver.resolveOptionalURL(from: path))?.absoluteString ?? path
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
