import Foundation

enum NetworkError: Error, Equatable, Sendable {
    case invalidRequest
    case abnormalRequest(message: String)
    case configuration(AppConfigurationError)
    case unauthorized
    case authenticationFailed(message: String)
    case accessTokenExpired
    case refreshTokenExpired
    case forbidden
    case notFound(message: String)
    case conflict(message: String)
    case rateLimited
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
        case .abnormalRequest(let message):
            return message
        case .configuration(let error):
            return error.userMessage
        case .unauthorized:
            return "Authentication failed."
        case .authenticationFailed(let message):
            return message
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
        case .decoding:
            return "The response could not be decoded."
        case .transport:
            return "A transport error occurred."
        }
    }
}

extension NetworkError {
    var isAuthenticationFailure: Bool {
        switch self {
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
            return true
        default:
            return false
        }
    }

    var shouldInvalidateSessionImmediately: Bool {
        switch self {
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
            return true
        default:
            return false
        }
    }

    var isConfigurationFailure: Bool {
        switch self {
        case .configuration:
            return true
        default:
            return false
        }
    }

    var isRetryableTransportFailure: Bool {
        switch self {
        case .transport:
            return true
        default:
            return false
        }
    }

    var appConfigurationError: AppConfigurationError? {
        if case .configuration(let error) = self {
            return error
        }
        return nil
    }
}
