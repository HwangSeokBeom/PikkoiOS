import Foundation

enum AuthProvider: String, CaseIterable, Equatable, Sendable, Identifiable {
    case kakao
    case apple

    var id: String { rawValue }
}

struct SocialLoginCredential: Equatable, Sendable {
    let provider: AuthProvider
    let accessToken: String?
    let idToken: String?
    let authorizationCode: String?
    let email: String?
    let nickname: String?
    let rawNonce: String?
    let userIdentifier: String?
}
