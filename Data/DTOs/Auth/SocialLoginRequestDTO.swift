import Foundation

typealias LoginRequestDTO = EmailLoginRequestDTO
typealias JoinRequestDTO = EmailSignUpRequestDTO

struct EmailLoginRequestDTO: Encodable, Sendable {
    let email: String
    let password: String
    let deviceToken: String?

    private enum CodingKeys: String, CodingKey {
        case email
        case password
        case deviceToken
    }
}

struct EmailSignUpRequestDTO: Encodable, Sendable {
    let email: String
    let password: String
    let nick: String
    let phoneNum: String?
    let deviceToken: String?

    private enum CodingKeys: String, CodingKey {
        case email
        case password
        case nick
        case phoneNum
        case deviceToken
    }
}

struct KakaoLoginRequestDTO: Encodable, Sendable {
    let oauthToken: String
    let deviceToken: String

    private enum CodingKeys: String, CodingKey {
        case oauthToken
        case deviceToken
    }
}

struct AppleLoginRequestDTO: Encodable, Sendable {
    let idToken: String
    let deviceToken: String?

    private enum CodingKeys: String, CodingKey {
        case idToken
        case deviceToken
    }
}

struct EmailValidationRequestDTO: Encodable, Sendable {
    let email: String
}

struct DeviceTokenRequestDTO: Encodable, Sendable {
    let deviceToken: String
}

struct ProfileRequestDTO: Encodable, Sendable {
    let nick: String
    let phoneNum: String?
    let profileImage: String?
}
