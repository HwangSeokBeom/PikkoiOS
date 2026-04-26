import Foundation

@MainActor
struct AuthBuilder {
    private let authRepository: AuthRepository
    private let socialAuthService: any SocialAuthProviding
    private let appConfiguration: AppConfiguration
    private let sessionStore: SessionStore
    private let presentationContext: AuthPresentationContext
    private let onAuthenticated: () -> Void

    init(
        authRepository: AuthRepository,
        socialAuthService: any SocialAuthProviding,
        appConfiguration: AppConfiguration,
        sessionStore: SessionStore,
        presentationContext: AuthPresentationContext = .generic,
        onAuthenticated: @escaping () -> Void = {}
    ) {
        self.authRepository = authRepository
        self.socialAuthService = socialAuthService
        self.appConfiguration = appConfiguration
        self.sessionStore = sessionStore
        self.presentationContext = presentationContext
        self.onAuthenticated = onAuthenticated
    }

    func build() -> AuthRootView {
        let router = AuthRouter(onAuthenticated: onAuthenticated)
        let interactor = AuthInteractor(
            authRepository: authRepository,
            socialAuthService: socialAuthService,
            appConfiguration: appConfiguration,
            presentationContext: presentationContext,
            allowsStubSignIn: allowsStubSignIn
        )
        let presenter = AuthPresenter(
            interactor: interactor,
            router: router,
            sessionStore: sessionStore
        )
        return AuthRootView(presenter: presenter)
    }

    private var allowsStubSignIn: Bool {
#if DEBUG
        appConfiguration.isInternalStubAuthEnabled
#else
        false
#endif
    }
}
