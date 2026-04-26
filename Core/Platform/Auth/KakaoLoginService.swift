import Foundation

#if canImport(KakaoSDKAuth)
import KakaoSDKAuth
import KakaoSDKCommon
import KakaoSDKUser

private struct KakaoLoginPayload: Sendable {
    let accessToken: String
    let idToken: String?
}
#endif

@MainActor
final class KakaoLoginService {
    private let appConfiguration: AppConfiguration
    private var hasPreparedSDK = false

    init(appConfiguration: AppConfiguration) {
        self.appConfiguration = appConfiguration
    }

    var availability: SocialAuthProviderAvailability {
        guard appConfiguration.hasValidKakaoNativeAppKey else {
            return .init(
                provider: .kakao,
                isEnabled: false,
                disabledReason: providerConfigurationMessage(
                    for: .kakao,
                    requiredKeys: ["KAKAO_NATIVE_APP_KEY"]
                )
            )
        }

#if canImport(KakaoSDKAuth)
        return .init(provider: .kakao, isEnabled: true, disabledReason: nil)
#else
        return .init(
            provider: .kakao,
            isEnabled: false,
            disabledReason: "Kakao SDK dependency is missing."
        )
#endif
    }

    func prepareIfNeeded() {
#if canImport(KakaoSDKAuth)
        guard !hasPreparedSDK,
              let kakaoNativeAppKey = appConfiguration.kakaoNativeAppKey else {
            return
        }

        KakaoSDK.initSDK(appKey: kakaoNativeAppKey)
        hasPreparedSDK = true
#endif
    }

    func signIn() async throws -> SocialLoginCredential {
        let availability = availability
        guard availability.isEnabled else {
            throw makeMissingConfigurationError(
                for: .kakao,
                message: availability.disabledReason ?? "카카오 로그인 설정을 확인해 주세요."
            )
        }

#if canImport(KakaoSDKAuth)
        prepareIfNeeded()

        let tokenPayload: KakaoLoginPayload = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<KakaoLoginPayload, Error>) in
            let completion: (OAuthToken?, Error?) -> Void = { token, error in
                if let error {
                    continuation.resume(
                        throwing: makeGenericCancellationError(for: .kakao, error: error)
                            ?? SocialAuthError.sdkFailure(
                                provider: .kakao,
                                message: error.localizedDescription
                            )
                    )
                    return
                }

                guard let token else {
                    continuation.resume(
                        throwing: SocialAuthError.sdkFailure(
                            provider: .kakao,
                            message: "카카오 인증 토큰을 받지 못했어요."
                        )
                    )
                    return
                }

                continuation.resume(
                    returning: KakaoLoginPayload(
                        accessToken: token.accessToken,
                        idToken: token.idToken
                    )
                )
            }

            if UserApi.isKakaoTalkLoginAvailable() {
                UserApi.shared.loginWithKakaoTalk(completion: completion)
            } else {
                UserApi.shared.loginWithKakaoAccount(completion: completion)
            }
        }

        let profile = await fetchUserProfile()

        return SocialLoginCredential(
            provider: .kakao,
            accessToken: tokenPayload.accessToken,
            idToken: tokenPayload.idToken,
            authorizationCode: nil,
            email: profile.email,
            nickname: profile.nickname,
            rawNonce: nil,
            userIdentifier: nil
        )
#else
        throw SocialAuthError.unsupported(
            provider: .kakao,
            message: "Kakao SDK dependency is missing."
        )
#endif
    }

    func handleOpenURL(_ url: URL) -> Bool {
#if canImport(KakaoSDKAuth)
        guard AuthApi.isKakaoTalkLoginUrl(url) else {
            return false
        }

        return AuthController.handleOpenUrl(url: url)
#else
        return false
#endif
    }

#if canImport(KakaoSDKAuth)
    private func fetchUserProfile() async -> (email: String?, nickname: String?) {
        await withCheckedContinuation { continuation in
            UserApi.shared.me { user, _ in
                continuation.resume(
                    returning: (
                        user?.kakaoAccount?.email,
                        user?.kakaoAccount?.profile?.nickname
                    )
                )
            }
        }
    }
#endif
}
