import Foundation

enum AppNotificationType: String, Codable, Equatable {
    case orderStatus
    case chatMessage
    case communityComment
    case communityLike
    case communityMention
    case payment
    case review
    case system
}

enum AppNotificationReadState: String, Codable, Equatable {
    case unread
    case read
}

enum AppNotificationSaveResult: Equatable {
    case saved(unreadCount: Int)
    case duplicate(id: String)
    case skipped(reason: String)
    case failed(reason: String)
}

struct AppNotification: Codable, Equatable, Identifiable {
    let id: String
    let type: AppNotificationType
    let title: String
    let body: String
    let createdAt: Date
    var readState: AppNotificationReadState
    let route: AppNotificationRoute
    let metadata: AppNotificationMetadata
}

enum AppNotificationRoute: Codable, Equatable {
    case orderDetail(orderCode: String)
    case orderList
    case chatRoom(roomId: String, storeId: String?, title: String?)
    case communityPost(postId: String, commentId: String?)
    case communityList
    case paymentReceipt(orderCode: String)
    case none
}

struct AppNotificationMetadata: Codable, Equatable {
    let orderCode: String?
    let orderStatus: String?
    let roomId: String?
    let storeId: String?
    let messageId: String?
    let senderId: String?
    let postId: String?
    let commentId: String?
    let actorUserId: String?
    let communityEventType: String?
    let rawPayload: [String: String]?

    init(
        orderCode: String? = nil,
        orderStatus: String? = nil,
        roomId: String? = nil,
        storeId: String? = nil,
        messageId: String? = nil,
        senderId: String? = nil,
        postId: String? = nil,
        commentId: String? = nil,
        actorUserId: String? = nil,
        communityEventType: String? = nil,
        rawPayload: [String: String]? = nil
    ) {
        self.orderCode = orderCode
        self.orderStatus = orderStatus
        self.roomId = roomId
        self.storeId = storeId
        self.messageId = messageId
        self.senderId = senderId
        self.postId = postId
        self.commentId = commentId
        self.actorUserId = actorUserId
        self.communityEventType = communityEventType
        self.rawPayload = rawPayload
    }
}

extension AppNotificationRoute {
    var debugDescription: String {
        switch self {
        case .orderDetail(let orderCode):
            return "orderDetail orderCode=\(orderCode)"
        case .orderList:
            return "orderList"
        case .chatRoom(let roomId, let storeId, let title):
            return "chatRoom roomId=\(roomId) storeId=\(storeId ?? "-") titleExists=\(title?.isEmpty == false)"
        case .communityPost(let postId, let commentId):
            return "communityPost postId=\(postId) commentId=\(commentId ?? "-")"
        case .communityList:
            return "communityList"
        case .paymentReceipt(let orderCode):
            return "paymentReceipt orderCode=\(orderCode)"
        case .none:
            return "none"
        }
    }
}
