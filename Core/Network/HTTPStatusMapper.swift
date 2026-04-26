import Foundation

enum HTTPStatusMapper {
    static func map(statusCode: Int, data: Data) -> NetworkError {
        let message = ResponseMessageParser.message(from: data, statusCode: statusCode)

        switch statusCode {
        case 400, 422:
            return .abnormalRequest(message: message)
        case 444:
            return .abnormalRequest(message: message)
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound(message: message)
        case 409:
            return .conflict(message: message)
        case 418:
            return .refreshTokenExpired
        case 419:
            return .accessTokenExpired
        case 420:
            return .configuration(.invalidSeSACKey)
        case 429:
            return .rateLimited
        case 445:
            return .businessAuthorization(message: message)
        case 500...599:
            return .server(message: message)
        default:
            return .server(message: message)
        }
    }
}

private enum ResponseMessageParser {
    static func message(from data: Data, statusCode: Int) -> String {
        guard !data.isEmpty else {
            return defaultMessage(for: statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return defaultMessage(for: statusCode)
        }

        return extractMessage(from: object) ?? defaultMessage(for: statusCode)
    }

    private static func extractMessage(from object: Any) -> String? {
        if let string = object as? String, !string.isEmpty {
            return string
        }

        if let array = object as? [Any] {
            for item in array {
                if let message = extractMessage(from: item) {
                    return message
                }
            }
        }

        if let dictionary = object as? [String: Any] {
            for key in ["message", "errorMessage", "error", "detail", "description"] {
                if let value = dictionary[key] as? String, !value.isEmpty {
                    return value
                }
            }

            if let payload = dictionary["payload"], let message = extractMessage(from: payload) {
                return message
            }
        }

        return nil
    }

    private static func defaultMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 444:
            return "The API path or method does not match the server contract."
        case 404:
            return "The requested resource was not found."
        case 409:
            return "The request conflicts with the current server state."
        case 445:
            return "The current user is not authorized for this business action."
        case 500...599:
            return "The server returned an unexpected error."
        default:
            return "The server returned an unexpected response."
        }
    }
}
