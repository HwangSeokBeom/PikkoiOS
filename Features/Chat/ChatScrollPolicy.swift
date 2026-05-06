import Foundation

enum ChatScrollInput: Equatable {
    case initialLoad(targetMessageId: String?)
    case optimisticAppend
    case messageReceived(senderIsCurrentUser: Bool, isNearBottom: Bool)
    case echoReplace(localTemporaryId: String?)
    case paginationPrepend
}

enum ChatScrollActionResult: Equatable {
    case scrollToBottom(reason: String)
    case scrollToMessage(id: String, reason: String)
    case showNewMessageIndicator
    case keepPosition(reason: String)
    case preservePosition
}

struct ChatScrollPolicy {
    static func action(for input: ChatScrollInput) -> ChatScrollActionResult {
        switch input {
        case .initialLoad(let targetMessageId):
            if let targetMessageId, !targetMessageId.isEmpty {
                return .scrollToMessage(id: targetMessageId, reason: "deepLink")
            }
            return .scrollToBottom(reason: "deepLink")
        case .optimisticAppend:
            return .scrollToBottom(reason: "optimistic")
        case .messageReceived(let senderIsCurrentUser, let isNearBottom):
            if senderIsCurrentUser || isNearBottom {
                return .scrollToBottom(reason: senderIsCurrentUser ? "selfMessage" : "nearBottom")
            }
            return .showNewMessageIndicator
        case .echoReplace:
            return .keepPosition(reason: "echoReplace")
        case .paginationPrepend:
            return .preservePosition
        }
    }
}

extension ChatScrollActionResult {
    var logValue: String {
        switch self {
        case .scrollToBottom:
            return "scrollToBottom"
        case .scrollToMessage:
            return "scrollToMessage"
        case .showNewMessageIndicator:
            return "showNewMessageIndicator"
        case .keepPosition:
            return "keepPosition"
        case .preservePosition:
            return "preservePosition"
        }
    }
}

extension ChatScrollTarget {
    var logValue: String {
        switch self {
        case .bottom:
            return "bottom"
        case .message(let id):
            return "message:\(id)"
        }
    }
}
