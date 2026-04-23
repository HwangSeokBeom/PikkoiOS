import Foundation

enum NetworkError: Error, Equatable, Sendable {
    case invalidRequest
    case unauthorized
    case accessTokenExpired
    case refreshTokenExpired
    case forbidden
    case notFound(message: String)
    case conflict(message: String)
    case rateLimited
    case serviceKeyInvalid
    case businessAuthorization(message: String)
    case server(message: String)
    case decoding
    case transport
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The request could not be created or accepted by the server."
        case .unauthorized:
            return "Authentication failed."
        case .accessTokenExpired:
            return "The access token has expired."
        case .refreshTokenExpired:
            return "The refresh token has expired."
        case .forbidden:
            return "The request is forbidden."
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return message
        case .rateLimited:
            return "The request was rate limited."
        case .serviceKeyInvalid:
            return "The SeSAC service key is invalid."
        case .decoding:
            return "The response could not be decoded."
        case .transport:
            return "A transport error occurred."
        }
    }
}
