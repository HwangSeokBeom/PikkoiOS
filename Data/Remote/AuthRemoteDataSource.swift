import Foundation

protocol AuthRemoteDataSourceProtocol: Sendable {
    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> LoginResponseDTO
    func signIn(email: String, password: String, deviceToken: String?) async throws -> LoginResponseDTO
    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> LoginResponseDTO
    func validateEmailAvailability(email: String) async throws
    func fetchMyProfile() async throws -> MyInfoResponseDTO
    func updateMyProfile(
        nick: String,
        phoneNumber: String?
    ) async throws -> MyInfoResponseDTO
    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> ProfileImageUploadResponseDTO
    func updateDeviceToken(_ deviceToken: String) async throws
    func searchUsers(nick: String?) async throws -> UserInfoListResponseDTO
    func logout() async throws
}

struct AuthRemoteDataSource: AuthRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> LoginResponseDTO {
        logDeviceTokenIncluded(endpoint: endpointPath(for: credential.provider), label: "login", deviceToken: deviceToken)
        let endpoint = Endpoint<LoginResponseDTO>(
            path: endpointPath(for: credential.provider),
            method: .post,
            body: RequestBody.json(try encodedSocialRequestBody(for: credential, deviceToken: deviceToken)),
            timeout: .default,
            authorizationPolicy: .none
        )
        return try await apiClient.execute(endpoint)
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> LoginResponseDTO {
        logDeviceTokenIncluded(endpoint: "/v1/users/login", label: "login", deviceToken: deviceToken)
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                EmailLoginRequestDTO(email: email, password: password, deviceToken: deviceToken)
            )
        )
        let endpoint = Endpoint<LoginResponseDTO>(
            path: "/v1/users/login",
            method: .post,
            body: body,
            timeout: .default,
            authorizationPolicy: .none
        )
        return try await apiClient.execute(endpoint)
    }

    func signUp(
        email: String,
        password: String,
        nick: String,
        phoneNumber: String?,
        deviceToken: String?
    ) async throws -> LoginResponseDTO {
        logDeviceTokenIncluded(endpoint: "/v1/users/join", label: "join", deviceToken: deviceToken)
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                EmailSignUpRequestDTO(
                    email: email,
                    password: password,
                    nick: nick,
                    phoneNum: phoneNumber,
                    deviceToken: deviceToken
                )
            )
        )
        let endpoint = Endpoint<LoginResponseDTO>(
            path: "/v1/users/join",
            method: .post,
            body: body,
            timeout: .default,
            authorizationPolicy: .none
        )
        return try await apiClient.execute(endpoint)
    }

    func validateEmailAvailability(email: String) async throws {
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                EmailValidationRequestDTO(email: email)
            )
        )
        let endpoint = Endpoint<MessageResponseDTO>(
            path: "/v1/users/validation/email",
            method: .post,
            body: body,
            timeout: .default,
            authorizationPolicy: .none
        )
        _ = try await apiClient.execute(endpoint)
    }

    func fetchMyProfile() async throws -> MyInfoResponseDTO {
        let endpoint = Endpoint<MyInfoResponseDTO>(
            path: "/v1/users/me/profile",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken,
            cachePolicy: .reloadIgnoringLocalCache
        )
        return try await apiClient.execute(endpoint)
    }

    func updateMyProfile(
        nick: String,
        phoneNumber: String?
    ) async throws -> MyInfoResponseDTO {
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                ProfileRequestDTO(
                    nick: nick,
                    phoneNum: phoneNumber
                )
            )
        )
        let endpoint = Endpoint<MyInfoResponseDTO>(
            path: "/v1/users/me/profile",
            method: .put,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func uploadProfileImage(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> ProfileImageUploadResponseDTO {
        guard !data.isEmpty else {
            throw NetworkError.invalidRequest
        }
        let maxProfileImageBytes = 1 * 1024 * 1024
        guard data.count <= maxProfileImageBytes else {
            throw NetworkError.invalidRequest
        }
        guard ["image/jpeg", "image/png"].contains(mimeType.lowercased()) else {
            throw NetworkError.invalidRequest
        }
        guard ["jpg", "jpeg", "png"].contains((fileName as NSString).pathExtension.lowercased()) else {
            throw NetworkError.invalidRequest
        }
        var builder = MultipartFormDataBuilder()
        builder.addFile(
            fieldName: UploadFieldName.profile,
            fileName: fileName,
            mimeType: mimeType,
            fileData: data
        )
#if DEBUG
        Logger(category: "ProfileImageUpload").debug("[ProfileImageUpload] prepared path=/v1/users/profile/image field=profile filename=\(fileName) mime=\(mimeType) byteSize=\(data.count) underLimit=\(data.count <= maxProfileImageBytes)")
        Logger(category: "ProfileImage").debug("[ProfileImage] upload start fieldName=profile fileName=\(fileName) mime=\(mimeType) bytes=\(data.count)")
#endif
        let endpoint = Endpoint<ProfileImageUploadResponseDTO>(
            path: "/v1/users/profile/image",
            method: .post,
            headers: [HTTPHeaderField.accept: "application/json"],
            body: builder.build(),
            timeout: .upload,
            authorizationPolicy: .accessToken
        )
        let response = try await apiClient.execute(endpoint)
        return response
    }

    func updateDeviceToken(_ deviceToken: String) async throws {
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                DeviceTokenRequestDTO(deviceToken: deviceToken)
            )
        )
        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/users/deviceToken",
            method: .put,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        _ = try await apiClient.execute(endpoint)
    }

    func searchUsers(nick: String?) async throws -> UserInfoListResponseDTO {
        let trimmedNick = nick?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [URLQueryItem]
        if let trimmedNick, !trimmedNick.isEmpty {
            query = [URLQueryItem(name: "nick", value: trimmedNick)]
        } else {
            query = []
        }

        let endpoint = Endpoint<UserInfoListResponseDTO>(
            path: "/v1/users/search",
            method: .get,
            query: query,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func logout() async throws {
        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/users/logout",
            method: .post,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        _ = try await apiClient.execute(endpoint)
    }

    private func endpointPath(for provider: AuthProvider) -> String {
        switch provider {
        case .kakao:
            return "/v1/users/login/kakao"
        case .apple:
            return "/v1/users/login/apple"
        }
    }

    private func encodedSocialRequestBody(
        for credential: SocialLoginCredential,
        deviceToken: String?
    ) throws -> Data {
        let encoder = NetworkCoding.makeJSONEncoder()

        switch credential.provider {
        case .kakao:
            guard let oauthToken = credential.accessToken, !oauthToken.isEmpty else {
                throw NetworkError.invalidRequest
            }
            let normalizedDeviceToken = deviceToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            return try encoder.encode(
                KakaoLoginRequestDTO(
                    oauthToken: oauthToken,
                    deviceToken: normalizedDeviceToken
                )
            )
        case .apple:
            guard let idToken = credential.idToken, !idToken.isEmpty else {
                throw NetworkError.invalidRequest
            }
            return try encoder.encode(
                AppleLoginRequestDTO(
                    idToken: idToken,
                    deviceToken: deviceToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
            )
        }
    }

    private func logDeviceTokenIncluded(endpoint: String, label: String, deviceToken: String?) {
#if DEBUG
        let includesDeviceToken = deviceToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        switch label {
        case "join":
            Logger(category: "PushToken").debug("[PushToken] join body includesDeviceToken=\(includesDeviceToken)")
        default:
            Logger(category: "PushToken").debug("[PushToken] login body includesDeviceToken=\(includesDeviceToken)")
        }
#endif
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
