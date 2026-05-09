import Foundation

enum HTTPStatusMapper {
    static func map(statusCode: Int, data: Data) -> NetworkError {
        let message = message(statusCode: statusCode, data: data)

        switch statusCode {
        case 400, 422:
            return .abnormalRequest(message: message)
        case 444:
            return .notFound(message: message)
        case 401:
            return .authenticationFailed(message: message)
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

    static func message(statusCode: Int, data: Data) -> String {
        ResponseMessageParser.message(from: data, statusCode: statusCode)
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

        return sanitizedMessage(
            extractMessage(from: object),
            statusCode: statusCode
        )
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
            return "요청한 정보를 찾을 수 없어요."
        case 404:
            return "요청한 정보를 찾을 수 없어요."
        case 409:
            return "이미 처리된 요청이거나 현재 상태와 맞지 않아요."
        case 445:
            return "이 작업을 진행할 권한이 없어요."
        case 429:
            return "요청이 너무 많아요. 잠시 후 다시 시도해 주세요."
        case 500...599:
            return "서버 응답이 원활하지 않습니다. 잠시 후 다시 시도해 주세요."
        default:
            return "요청을 처리하지 못했어요."
        }
    }

    private static func sanitizedMessage(_ message: String?, statusCode: Int) -> String {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return defaultMessage(for: statusCode)
        }

        if shouldSuppressRawServerMessage(message, statusCode: statusCode) {
            return defaultMessage(for: statusCode)
        }

        return message
    }

    private static func shouldSuppressRawServerMessage(_ message: String, statusCode: Int) -> Bool {
        if statusCode == 444 {
            return true
        }

        let blockedFragments = [
            "돌아가",
            "자네가 올 곳",
            "여긴 자네"
        ]
        return blockedFragments.contains { message.contains($0) }
    }
}
