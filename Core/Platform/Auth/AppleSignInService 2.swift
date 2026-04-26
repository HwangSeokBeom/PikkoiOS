import AuthenticationServices
import CryptoKit
import Foundation

@MainActor
final class AppleSignInService {
    private let appConfiguration: AppConfiguration

    init(appConfiguration: AppConfiguration) {
        self.appConfiguration = appConfiguration
    }

    var availability: SocialAuthProviderAvailability {
        return .init(provider: .apple, isEnabled: true, disabledReason: nil)
    }

    func prepareIfNeeded() {}

    func signIn() async throws -> SocialLoginCredential {
        let availability = availability
        guard availability.isEnabled else {
            throw makeMissingConfigurationError(
                for: .apple,
                message: availability.disabledReason ?? "Apple 로그인 설정을 확인해 주세요."
            )
        }

        guard let presentationAnchor = AuthPresentationContextResolver.activeWindow() else {
            throw SocialAuthError.presentationContextUnavailable(provider: .apple)
        }

        let coordinator = AppleAuthorizationCoordinator(presentationAnchor: presentationAnchor)
        return try await coordinator.start()
    }
}

@MainActor
private final class AppleAuthorizationCoordinator: NSObject {
    private let presentationAnchor: ASPresentationAnchor
    private var continuation: CheckedContinuation<SocialLoginCredential, Error>?
    private var rawNonce = ""

    init(presentationAnchor: ASPresentationAnchor) {
        self.presentationAnchor = presentationAnchor
    }

    func start() async throws -> SocialLoginCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            rawNonce = Self.randomNonceString()

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(rawNonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms = (0..<16).map { _ in UInt8.random(in: 0...255) }
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }
}

extension AppleAuthorizationCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(
                throwing: SocialAuthError.sdkFailure(
                    provider: .apple,
                    message: "Apple 인증 자격 정보를 해석하지 못했어요."
                )
            )
            continuation = nil
            return
        }

        let identityToken = credential.identityToken.flatMap {
            String(data: $0, encoding: .utf8)
        }
        let authorizationCode = credential.authorizationCode.flatMap {
            String(data: $0, encoding: .utf8)
        }
        let nickname = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        continuation?.resume(
            returning: SocialLoginCredential(
                provider: .apple,
                accessToken: nil,
                idToken: identityToken,
                authorizationCode: authorizationCode,
                email: credential.email,
                nickname: nickname.isEmpty ? nil : nickname,
                rawNonce: rawNonce,
                userIdentifier: credential.user
            )
        )
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let error = error as? ASAuthorizationError,
           error.code == .canceled {
            continuation?.resume(throwing: SocialAuthError.cancelled(provider: .apple))
        } else {
            continuation?.resume(
                throwing: SocialAuthError.sdkFailure(
                    provider: .apple,
                    message: error.localizedDescription
                )
            )
        }
        continuation = nil
    }
}

extension AppleAuthorizationCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationAnchor
    }
}
