import Foundation

typealias LoginDTO = LoginResponseDTO
typealias JoinResponseDTO = LoginResponseDTO

struct LoginResponseDTO: Decodable, Sendable {
    let userID: String
    let email: String
    let nick: String
    let profileImage: String?
    let accessToken: String
    let refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case nick
        case profileImage
        case accessToken
        case refreshToken
    }
}

struct MyInfoResponseDTO: Decodable, Sendable {
    let userID: String
    let email: String
    let nick: String
    let profileImage: String?
    let phoneNum: String?

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case nick
        case profileImage
        case phoneNum
    }
}

struct ProfileImageUploadResponseDTO: Decodable, Sendable {
    let profileImage: String?
}

struct MessageResponseDTO: Decodable, Sendable {
    let message: String?
}

struct UserInfoListResponseDTO: Decodable, Sendable {
    let data: [UserInfoResponseDTO]
}

struct RefreshTokenResponseDTO: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        accessToken = try container.decodeString(forKeys: ["accessToken", "access_token", "token"])
        refreshToken = container.decodeOptionalString(forKeys: ["refreshToken", "refresh_token"])
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decodeString(forKeys keys: [String]) throws -> String {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value = try decodeIfPresent(String.self, forKey: codingKey), !value.isEmpty {
                return value
            }
        }

        throw DecodingError.keyNotFound(
            DynamicCodingKey(stringValue: keys[0])!,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Expected one of \(keys)")
        )
    }

    func decodeOptionalString(forKeys keys: [String]) -> String? {
        for key in keys {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value = try? decode(String.self, forKey: codingKey),
               !value.isEmpty {
                return value
            }
        }

        return nil
    }
}
