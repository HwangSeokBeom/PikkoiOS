import Foundation

@MainActor
final class AuthPresenter: ObservableObject {
    @Published private(set) var viewState = AuthViewState()

    private let interactor: AuthInteracting
    private let router: AuthRouting
    private let sessionStore: SessionStore
    private var hasLoaded = false

    init(
        interactor: AuthInteracting,
        router: AuthRouting,
        sessionStore: SessionStore
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
    }

    func send(_ action: AuthAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
        case .providerTapped(let provider):
            await signIn(with: provider)
        case .emailChanged(let email):
            viewState.email = email
            viewState.errorMessage = nil
            viewState.emailValidationState = .idle
        case .validateEmailTapped:
            await validateEmailAvailability()
        case .passwordChanged(let password):
            viewState.password = password
            viewState.errorMessage = nil
        case .passwordConfirmationChanged(let passwordConfirmation):
            viewState.passwordConfirmation = passwordConfirmation
            viewState.errorMessage = nil
        case .nickChanged(let nick):
            viewState.nick = nick
            viewState.errorMessage = nil
        case .emailSignInTapped:
            await submitEmailSignIn()
        case .signUpTapped:
            await submitSignUp()
        case .clearError:
            viewState.errorMessage = nil
        case .stubSignInTapped:
            await signInWithStub()
        }
    }

    private func signIn(with provider: AuthProvider) async {
        guard !viewState.isLoading else { return }
        let wasAuthenticatedAtStart = sessionStore.isAuthenticated
        if provider == .apple {
            Logger.shared.debug("[Auth] apple login started")
            await sessionStore.prepareForLoginAttempt()
        }
        setLoading(provider: provider)

        do {
            let session = try await interactor.signIn(
                with: provider,
                deviceToken: sessionStore.deviceToken
            )
            guard await sessionStore.establishAuthenticatedSession(session) else {
                throw NetworkError.transport
            }
            clearLoading()
            Logger.shared.debug("[Auth] home/profile bootstrap allowed")
            router.completeAuthentication()
        } catch {
            clearLoading()
            if provider == .apple, !wasAuthenticatedAtStart {
                await sessionStore.clearSession()
            }
            if handleSilentCancellation(error, provider: provider) {
                return
            }
            let message = resolveErrorMessage(from: error)
            viewState.errorMessage = message == viewState.configurationMessage ? nil : message
            if provider == .apple {
                Logger.shared.warning("[Auth] social login failed provider=apple reason=\(error.localizedDescription)")
            }
            logFailure(error, provider: provider)
        }
    }

    private func submitEmailSignIn() async {
        guard !viewState.isLoading else { return }
        setFormSubmitting()

        do {
            let session = try await interactor.signIn(
                email: viewState.email,
                password: viewState.password,
                deviceToken: sessionStore.deviceToken
            )
            guard await sessionStore.establishAuthenticatedSession(session) else {
                throw NetworkError.transport
            }
            clearLoading()
            router.completeAuthentication()
        } catch {
            clearLoading()
            let message = resolveErrorMessage(from: error)
            viewState.errorMessage = message == viewState.configurationMessage ? nil : message
            Logger.shared.warning("Email auth failed: \(error.localizedDescription)")
        }
    }

    private func submitSignUp() async {
        guard !viewState.isLoading else { return }
        setFormSubmitting()

        do {
            try validatePasswordConfirmation()
            guard viewState.emailValidationState.isAvailable else {
                throw AuthInputValidationError.validation(message: "이메일 중복 확인을 완료해 주세요.")
            }
            let session = try await interactor.signUp(
                email: viewState.email,
                password: viewState.password,
                nick: viewState.nick,
                deviceToken: sessionStore.deviceToken
            )
            guard await sessionStore.establishAuthenticatedSession(session) else {
                throw NetworkError.transport
            }
            clearLoading()
            router.completeAuthentication()
        } catch {
            clearLoading()
            let message = resolveErrorMessage(from: error)
            viewState.errorMessage = message == viewState.configurationMessage ? nil : message
            Logger.shared.warning("Email sign-up failed: \(error.localizedDescription)")
        }
    }

    private func validateEmailAvailability() async {
        guard !viewState.isLoading else { return }

        viewState.errorMessage = nil
        viewState.emailValidationState = .validating

        do {
            try await interactor.validateEmailAvailability(email: viewState.email)
            viewState.emailValidationState = .available(message: "사용 가능한 이메일이에요.")
        } catch {
            let message = resolveErrorMessage(from: error)
            viewState.emailValidationState = .unavailable(message: message)
            if error is AuthInputValidationError {
                viewState.errorMessage = message
            }
            Logger.shared.info("Email validation result: \(message)")
        }
    }

    private func signInWithStub() async {
        guard viewState.showsStubSignIn,
              !viewState.isLoading else { return }

        viewState.isLoading = true
        viewState.loadingProvider = nil
        viewState.isFormSubmitting = false
        viewState.errorMessage = nil

        do {
            let session = try await interactor.signInStub()
            guard await sessionStore.establishAuthenticatedSession(session) else {
                throw NetworkError.transport
            }
            viewState.isLoading = false
            router.completeAuthentication()
        } catch {
            viewState.isLoading = false
            let message = resolveErrorMessage(from: error)
            viewState.errorMessage = message == viewState.configurationMessage ? nil : message
            Logger.shared.warning("Stub sign-in failed: \(error.localizedDescription)")
        }
    }

    private func setLoading(provider: AuthProvider) {
        viewState.isLoading = true
        viewState.loadingProvider = provider
        viewState.isFormSubmitting = false
        viewState.errorMessage = nil
        viewState.providerButtons = viewState.providerButtons.map { button in
            var updated = button
            updated.isLoading = button.provider == provider
            return updated
        }
    }

    private func setFormSubmitting() {
        viewState.isLoading = true
        viewState.loadingProvider = nil
        viewState.isFormSubmitting = true
        viewState.errorMessage = nil
        viewState.providerButtons = viewState.providerButtons.map { button in
            var updated = button
            updated.isLoading = false
            return updated
        }
    }

    private func clearLoading() {
        viewState.isLoading = false
        viewState.loadingProvider = nil
        viewState.isFormSubmitting = false
        viewState.providerButtons = viewState.providerButtons.map { button in
            var updated = button
            updated.isLoading = false
            return updated
        }
    }

    private func handleSilentCancellation(_ error: Error, provider: AuthProvider) -> Bool {
        guard let socialError = error as? SocialAuthError,
              socialError.isUserCancelled else {
            return false
        }

        Logger.shared.info("\(provider.displayName) sign-in cancelled by user.")
        viewState.errorMessage = nil
        return true
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let socialError = error as? SocialAuthError {
            switch socialError {
            case .cancelled:
                return ""
            case .configurationMissing,
                 .unsupported,
                 .presentationContextUnavailable:
                return socialError.errorDescription ?? "로그인 설정을 확인해 주세요."
            case .sdkFailure(_, let message):
                if isNetworkLike(message) {
                    return "네트워크 상태를 확인해 주세요."
                }
                return "로그인 처리에 실패했어요. 잠시 후 다시 시도해 주세요."
            }
        }

        if let validationError = error as? AuthInputValidationError,
           let description = validationError.errorDescription,
           !description.isEmpty {
            return description
        }

        if let networkError = error as? NetworkError {
            switch networkError {
            case .transport:
                return "네트워크 상태를 확인해 주세요."
            case .configuration(let configurationError):
                return configurationError.authUserMessage
            case .notFound(let message),
                 .conflict(let message),
                 .businessAuthorization(let message),
                 .server(let message):
                return message
            case .forbidden,
                 .rateLimited,
                 .unauthorized,
                 .accessTokenExpired,
                 .refreshTokenExpired:
                return "로그인 처리에 실패했어요. 잠시 후 다시 시도해 주세요."
            case .invalidRequest,
                 .abnormalRequest,
                 .decoding:
                return "로그인에 실패했어요. 다시 시도해 주세요."
            }
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return "로그인에 실패했어요. 다시 시도해 주세요."
    }

    private func logFailure(_ error: Error, provider: AuthProvider) {
        let message = error.localizedDescription

        if let socialError = error as? SocialAuthError,
           socialError.isUserCancelled {
            Logger.shared.info("\(provider.displayName) sign-in cancelled by user.")
            return
        }

        if let networkError = error as? NetworkError {
            switch networkError {
            case .transport:
                Logger.shared.info("\(provider.displayName) sign-in network issue: \(message)")
            case .configuration:
                Logger.shared.warning("\(provider.displayName) sign-in configuration issue: \(message)")
            default:
                Logger.shared.warning("\(provider.displayName) sign-in failed: \(message)")
            }
            return
        }

        Logger.shared.warning("\(provider.displayName) sign-in failed: \(message)")
    }

    private func isNetworkLike(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("network")
            || normalized.contains("internet")
            || normalized.contains("connection")
            || normalized.contains("transport")
            || normalized.contains("offline")
            || normalized.contains("연결")
            || normalized.contains("네트워크")
    }

    private func validatePasswordConfirmation() throws {
        guard viewState.password == viewState.passwordConfirmation else {
            throw AuthInputValidationError.validation(message: "비밀번호 확인이 일치하지 않아요.")
        }
    }
}
