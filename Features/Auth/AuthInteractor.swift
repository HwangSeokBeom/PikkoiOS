import Foundation

@MainActor
protocol AuthInteracting {
    func loadInitialState() async -> AuthViewState
    func signIn(with provider: AuthProvider, deviceToken: String?) async throws -> UserSession
    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession
    func signUp(email: String, password: String, nick: String, deviceToken: String?) async throws -> UserSession
    func validateEmailAvailability(email: String) async throws
    func signInStub() async throws -> UserSession
}

@MainActor
struct AuthInteractor: AuthInteracting {
    private let authRepository: AuthRepository
    private let socialAuthService: any SocialAuthProviding
    private let appConfiguration: AppConfiguration
    private let presentationContext: AuthPresentationContext
    private let allowsStubSignIn: Bool

    init(
        authRepository: AuthRepository,
        socialAuthService: any SocialAuthProviding,
        appConfiguration: AppConfiguration,
        presentationContext: AuthPresentationContext = .generic,
        allowsStubSignIn: Bool = false
    ) {
        self.authRepository = authRepository
        self.socialAuthService = socialAuthService
        self.appConfiguration = appConfiguration
        self.presentationContext = presentationContext
        self.allowsStubSignIn = allowsStubSignIn
    }

    func loadInitialState() async -> AuthViewState {
        socialAuthService.prepareIfNeeded()
        var state = AuthViewState(
            title: presentationContext.title,
            subtitle: presentationContext.subtitle
        )
        state.showsStubSignIn = allowsStubSignIn
        state.showsDismissButton = presentationContext != .generic
        state.providerButtons = AuthProvider.visibleProviders.map { provider in
            let availability = socialAuthService.availability(for: provider)
            return AuthProviderButtonState(
                provider: provider,
                title: "\(provider.displayName)로 계속하기",
                systemImage: provider.systemImageName,
                isEnabled: availability.isEnabled,
                helperText: availability.disabledReason
            )
        }
        state.configurationMessage = appConfiguration.networkConfigurationError?.authUserMessage
        return state
    }

    func signIn(with provider: AuthProvider, deviceToken: String?) async throws -> UserSession {
        let credential = try await socialAuthService.signIn(with: provider)
        return try await authRepository.signIn(with: credential, deviceToken: deviceToken)
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> UserSession {
        try validateEmail(email)
        try validatePassword(password)
        return try await authRepository.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            deviceToken: deviceToken
        )
    }

    func signUp(email: String, password: String, nick: String, deviceToken: String?) async throws -> UserSession {
        try validateEmail(email)
        try validatePassword(password)
        try validateNick(nick)
        return try await authRepository.signUp(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            nick: nick.trimmingCharacters(in: .whitespacesAndNewlines),
            phoneNumber: nil,
            deviceToken: deviceToken
        )
    }

    func validateEmailAvailability(email: String) async throws {
        try validateEmail(email)

        do {
            try await authRepository.validateEmailAvailability(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch let error as NetworkError {
            switch error {
            case .conflict(let message):
                throw AuthEmailValidationError.alreadyInUse(
                    message: message.isEmpty ? "이미 사용 중인 이메일이에요." : message
                )
            case .invalidRequest:
                throw AuthEmailValidationError.invalid(message: "이메일 형식을 다시 확인해 주세요.")
            case .configuration(let configurationError):
                throw AuthEmailValidationError.unavailable(message: configurationError.authUserMessage)
            case .transport:
                throw AuthEmailValidationError.unavailable(message: "네트워크 상태를 확인해 주세요.")
            case .notFound(let message),
                 .businessAuthorization(let message),
                 .server(let message),
                 .abnormalRequest(let message):
                throw AuthEmailValidationError.unavailable(message: message)
            case .forbidden,
                 .rateLimited,
                 .unauthorized,
                 .accessTokenExpired,
                 .refreshTokenExpired,
                 .decoding:
                throw AuthEmailValidationError.unavailable(
                    message: "이메일 중복 확인에 실패했어요. 잠시 후 다시 시도해 주세요."
                )
            }
        }
    }

    func signInStub() async throws -> UserSession {
        try await authRepository.signInStub()
    }

    private func validateEmail(_ email: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(
            pattern: "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$",
            value: trimmed,
            options: [.caseInsensitive]
        ) else {
            throw AuthInputValidationError.validation(message: "이메일 형식을 확인해 주세요.")
        }
    }

    private func validatePassword(_ password: String) throws {
        guard matches(
            pattern: "^(?=.*[A-Za-z])(?=.*\\d)(?=.*[@$!%*#?&])[A-Za-z\\d@$!%*#?&]{8,}$",
            value: password
        ) else {
            throw AuthInputValidationError.validation(
                message: "비밀번호는 8자 이상이며 영문, 숫자, 특수문자(@$!%*#?&)를 포함해야 해요."
            )
        }
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

    private func matches(
        pattern: String,
        value: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}

enum AuthInputValidationError: LocalizedError, Equatable {
    case validation(message: String)

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        }
    }
}

enum AuthEmailValidationError: LocalizedError, Equatable {
    case invalid(message: String)
    case alreadyInUse(message: String)
    case unavailable(message: String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .alreadyInUse(let message), .unavailable(let message):
            return message
        }
    }
}
