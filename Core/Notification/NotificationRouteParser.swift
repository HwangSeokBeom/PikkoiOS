import Foundation

enum NotificationRouteSource: String, Equatable, Sendable {
    case remoteFCM
    case localNotification
    case appInternalDebug
    case notificationCenter
}

struct NotificationRouteParser {
    struct Result: Equatable, Sendable {
        let route: AppNotificationRoute
        let rawType: String?
        let keys: [String]
    }

    private static let typeKeys = ["type", "notificationType", "notification_type", "eventType", "event_type", "event", "category"]
    private static let chatRoomKeys = ["room_id", "roomId", "chatRoomId", "chat_room_id"]
    private static let storeIdKeys = ["storeId", "store_id"]
    private static let titleKeys = ["title", "roomTitle", "room_title", "storeName", "store_name"]
    private static let postKeys = ["post_id", "postId", "communityPostId", "community_post_id"]
    private static let commentKeys = ["comment_id", "commentId", "replyId", "reply_id"]
    private static let orderCodeKeys = ["order_code", "orderCode"]
    private static let orderIdKeys = ["order_id", "orderId"]
    private static let communityEventKeys = ["communityEventType", "community_event_type", "eventType", "event_type"]
    private static let messageIdKeys = [
        "gcm.message_id",
        "google.message_id",
        "message_id",
        "messageId",
        "aps.thread-id",
        "google.c.a.c_id"
    ]

    static func parse(
        userInfo: [AnyHashable: Any],
        source: NotificationRouteSource,
        allowsLocalDebugRoute: Bool = false
    ) -> Result? {
        parse(
            rawPayload: flattenedPayload(from: userInfo),
            source: source,
            allowsLocalDebugRoute: allowsLocalDebugRoute
        )
    }

    static func parse(
        rawPayload: [String: String],
        source: NotificationRouteSource,
        allowsLocalDebugRoute: Bool = false
    ) -> Result? {
        let keys = rawPayload.keys.sorted()
        let rawType = value(for: typeKeys, in: rawPayload)
        let typeValue = normalized(rawType)
        let communityEventValue = normalized(value(for: communityEventKeys, in: rawPayload))
        let keyCount = keys.count

        guard source == .remoteFCM || source == .notificationCenter || allowsLocalDebugRoute else {
            Logger(category: "PushRoute").debug("[PushRoute] ignored source=\(source.rawValue) reason=debugOnly")
            return nil
        }

        Logger(category: "PushDeepLink").debug("[PushDeepLink] parse start source=remote keyCount=\(keyCount)")

        if let roomId = value(for: chatRoomKeys, in: rawPayload) {
            if rawType == nil || typeValue == "unknown" {
                Logger(category: "PushPayload").warning("[PushPayload] missingOrUnknownType messageId=\(messageID(from: rawPayload) ?? "unknown") roomIdExists=true action=useRoomIdAsChatRoute")
            }
            let route: AppNotificationRoute = .chatRoom(
                roomId: roomId,
                storeId: value(for: storeIdKeys, in: rawPayload),
                title: value(for: titleKeys, in: rawPayload)
            )
            Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=chat requiredIdExists=true")
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=chat roomIdExists=true")
            return Result(route: route, rawType: rawType, keys: keys)
        }

        if isChat(typeValue) {
            logParseFailed(source: source, rawType: rawType, reason: "missingRoomId", keys: keys)
            return Result(route: .none, rawType: rawType, keys: keys)
        }

        if let postId = value(for: postKeys, in: rawPayload) {
            let commentId = value(for: commentKeys, in: rawPayload)
            let result = isCommunityLike(typeValue: typeValue, communityEventValue: communityEventValue) ? "postLike" : "postComment"
            Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=\(result) requiredIdExists=true")
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=communityPost postIdExists=true commentIdExists=\(commentId != nil)")
            return Result(route: .communityPost(postId: postId, commentId: commentId), rawType: rawType, keys: keys)
        }

        if isCommunity(typeValue, communityEventValue: communityEventValue) {
            logParseFailed(source: source, rawType: rawType, reason: "missingPostId", keys: keys)
            return Result(route: .none, rawType: rawType, keys: keys)
        }

        if let orderIdentifier = value(for: orderCodeKeys, in: rawPayload) ?? value(for: orderIdKeys, in: rawPayload) {
            Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=order requiredIdExists=true")
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=orderDetail orderIdExists=true")
            return Result(route: .orderDetail(orderCode: orderIdentifier), rawType: rawType, keys: keys)
        }

        if isOrder(typeValue) {
            logParseFailed(source: source, rawType: rawType, reason: "missingOrderCode", keys: keys)
            return Result(route: .orderList, rawType: rawType, keys: keys)
        }

        logParseFailed(source: source, rawType: rawType, reason: hasCustomRoutingData(rawPayload) ? "unknown" : "noCustomData", keys: keys)
        Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=notice requiredIdExists=false")
        Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=unknown")
        return Result(route: .none, rawType: rawType, keys: keys)
    }

    static func flattenedPayload(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var values: [String: String] = [:]
        flatten(userInfo, into: &values)
        return values
    }

    static func messageID(from rawPayload: [String: String]) -> String? {
        value(for: messageIdKeys, in: rawPayload)
    }

    static func normalizedRoomID(from rawPayload: [String: String]) -> String? {
        value(for: chatRoomKeys, in: rawPayload)
    }

    private static func flatten(_ dictionary: [AnyHashable: Any], into values: inout [String: String]) {
        for (key, value) in dictionary {
            guard let key = key as? String else { continue }
            if let string = value as? String {
                values[key] = string
            } else if let number = value as? NSNumber {
                values[key] = number.stringValue
            } else if let nested = value as? [AnyHashable: Any] {
                flatten(nested, into: &values)
            } else if let nested = value as? [String: Any] {
                flatten(Dictionary(uniqueKeysWithValues: nested.map { (AnyHashable($0.key), $0.value) }), into: &values)
            }
        }
    }

    private static func value(for keys: [String], in payload: [String: String]) -> String? {
        for key in keys {
            if let value = payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            ?? ""
    }

    private static func isChat(_ type: String) -> Bool {
        containsAny(["chat", "chat_message", "message"], in: type)
    }

    private static func isCommunity(_ type: String, communityEventValue: String) -> Bool {
        containsAny(["community", "post", "comment", "like", "mention"], in: type)
            || containsAny(["community_comment", "post_comment", "community_like", "post_like", "comment", "like", "mention"], in: communityEventValue)
    }

    private static func isOrder(_ type: String) -> Bool {
        containsAny(["order", "order_status", "internal_order_status_changed", "order_status_changed", "payment", "review"], in: type)
    }

    private static func isCommunityLike(typeValue: String, communityEventValue: String) -> Bool {
        containsAny(["like"], in: typeValue) || containsAny(["like"], in: communityEventValue)
    }

    private static func hasCustomRoutingData(_ payload: [String: String]) -> Bool {
        let routingKeys = Set(typeKeys + chatRoomKeys + postKeys + commentKeys + orderCodeKeys + orderIdKeys + communityEventKeys)
        return payload.keys.contains { routingKeys.contains($0) }
    }

    private static func containsAny(_ needles: [String], in value: String) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func logParseFailed(source: NotificationRouteSource, rawType: String?, reason: String, keys: [String]) {
        Logger(category: "PushDeepLink").warning("[PushDeepLink] parse failed reason=\(reason) keys=\(keys.joined(separator: ","))")
        Logger(category: "PushRoute").warning("[PushRoute] parseFailed source=\(source.rawValue) type=\(rawType ?? "unknown") reason=\(reason) keys=\(keys.joined(separator: ","))")
    }
}
