import Foundation
import UIKit

struct SocialAuthProviderAvailability: Equatable, Sendable {
    let provider: AuthProvider
    let isEnabled: Bool
    let disabledReason: String?
}

enum SocialAuthError: LocalizedError, Equatable, Sendable {
    case configurationMissing(provider: AuthProvider, message: String)
    case presentationContextUnavailable(provider: AuthProvider)
    case cancelled(provider: AuthProvider)
    case sdkFailure(provider: AuthProvider, message: String)
    case unsupported(provider: AuthProvider, message: String)

    var errorDescription: String? {
        switch self {
        case .configurationMissing(_, let message),
             .sdkFailure(_, let message),
             .unsupported(_, let message):
            return message
        case .presentationContextUnavailable(let provider):
            return "\(provider.displayName) 로그인을 표시할 화면을 찾지 못했어요."
        case .cancelled(let provider):
            return "\(provider.displayName) 로그인이 취소되었습니다."
        }
    }
}

extension SocialAuthError {
    var isUserCancelled: Bool {
        if case .cancelled = self {
            return true
        }

        return false
    }
}

@MainActor
protocol SocialAuthProviding: Sendable {
    func prepareIfNeeded()
    func availability(for provider: AuthProvider) -> SocialAuthProviderAvailability
    func signIn(with provider: AuthProvider) async throws -> SocialLoginCredential
    func handleOpenURL(_ url: URL) -> Bool
}

@MainActor
final class SocialAuthService: SocialAuthProviding {
    private let kakaoLoginService: KakaoLoginService
    private let appleSignInService: AppleSignInService

    init(
        appConfiguration: AppConfiguration,
        kakaoLoginService: KakaoLoginService? = nil,
        appleSignInService: AppleSignInService? = nil
    ) {
        self.kakaoLoginService = kakaoLoginService ?? KakaoLoginService(appConfiguration: appConfiguration)
        self.appleSignInService = appleSignInService ?? AppleSignInService(appConfiguration: appConfiguration)
    }

    func prepareIfNeeded() {
        kakaoLoginService.prepareIfNeeded()
        appleSignInService.prepareIfNeeded()
    }

    func availability(for provider: AuthProvider) -> SocialAuthProviderAvailability {
        switch provider {
        case .kakao:
            return kakaoLoginService.availability
        case .apple:
            return appleSignInService.availability
        }
    }

    func signIn(with provider: AuthProvider) async throws -> SocialLoginCredential {
        switch provider {
        case .kakao:
            return try await kakaoLoginService.signIn()
        case .apple:
            return try await appleSignInService.signIn()
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        if kakaoLoginService.handleOpenURL(url) {
            return true
        }

        return false
    }
}

extension AuthProvider {
    var displayName: String {
        switch self {
        case .kakao:
            return "카카오"
        case .apple:
            return "Apple"
        }
    }
}

func providerConfigurationMessage(
    for provider: AuthProvider,
    requiredKeys: [String]
) -> String {
#if DEBUG
    let keys = requiredKeys.joined(separator: ", ")
    return "Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig에 \(keys)를 설정해 주세요."
#else
    return "\(provider.displayName) 로그인 설정을 확인해 주세요."
#endif
}

@MainActor
enum AuthPresentationContextResolver {
    static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    static func topViewController(
        from rootViewController: UIViewController? = activeWindow()?.rootViewController
    ) -> UIViewController? {
        if let navigationController = rootViewController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = rootViewController as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        if let presentedViewController = rootViewController?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        return rootViewController
    }
}

func makeMissingConfigurationError(
    for provider: AuthProvider,
    message: String
) -> SocialAuthError {
    .configurationMissing(provider: provider, message: message)
}

func makeGenericCancellationError(
    for provider: AuthProvider,
    error: Error
) -> SocialAuthError? {
    let nsError = error as NSError
    let loweredDescription = nsError.localizedDescription.lowercased()
    if nsError.code == NSUserCancelledError ||
        loweredDescription.contains("cancel") ||
        loweredDescription.contains("canceled") ||
        loweredDescription.contains("cancelled") {
        return .cancelled(provider: provider)
    }

    return nil
}
