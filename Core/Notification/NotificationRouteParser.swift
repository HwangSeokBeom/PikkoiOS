import Foundation

enum NotificationRouteSource: String, Equatable {
    case remoteFCM
    case localNotification
    case appInternalDebug
    case notificationCenter
}

struct NotificationRouteParser {
    struct Result: Equatable {
        let route: AppNotificationRoute
        let rawType: String?
        let keys: [String]
    }

    private static let typeKeys = ["type", "notificationType", "notification_type", "eventType", "event_type", "event", "category"]
    private static let chatRoomKeys = ["chatRoomId", "chat_room_id", "roomId", "room_id"]
    private static let storeIdKeys = ["storeId", "store_id"]
    private static let titleKeys = ["title", "roomTitle", "room_title", "storeName", "store_name"]
    private static let postKeys = ["postId", "post_id", "communityPostId", "community_post_id"]
    private static let commentKeys = ["commentId", "comment_id", "replyId", "reply_id"]
    private static let orderKeys = ["orderCode", "order_code", "orderId", "order_id"]
    private static let communityEventKeys = ["communityEventType", "community_event_type", "eventType", "event_type"]

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

        guard source == .remoteFCM || source == .notificationCenter || allowsLocalDebugRoute else {
            Logger(category: "PushRoute").debug("[PushRoute] ignored source=\(source.rawValue) reason=debugOnly")
            return nil
        }

        if isChat(typeValue) {
            guard let roomId = value(for: chatRoomKeys, in: rawPayload) else {
                logParseFailed(source: source, rawType: rawType, reason: "missingRequiredKey", keys: keys)
                return nil
            }
            let route: AppNotificationRoute = .chatRoom(
                roomId: roomId,
                storeId: value(for: storeIdKeys, in: rawPayload),
                title: value(for: titleKeys, in: rawPayload)
            )
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=chat roomIdExists=true")
            return Result(route: route, rawType: rawType, keys: keys)
        }

        if isCommunity(typeValue, communityEventValue: communityEventValue) {
            guard let postId = value(for: postKeys, in: rawPayload) else {
                logParseFailed(source: source, rawType: rawType, reason: "missingRequiredKey", keys: keys)
                return nil
            }
            let commentId = value(for: commentKeys, in: rawPayload)
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=communityPost postIdExists=true commentIdExists=\(commentId != nil)")
            return Result(route: .communityPost(postId: postId, commentId: commentId), rawType: rawType, keys: keys)
        }

        if isOrder(typeValue) {
            guard let orderIdentifier = value(for: orderKeys, in: rawPayload) else {
                logParseFailed(source: source, rawType: rawType, reason: "missingRequiredKey", keys: keys)
                return nil
            }
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=orderDetail orderIdExists=true")
            return Result(route: .orderDetail(orderCode: orderIdentifier), rawType: rawType, keys: keys)
        }

        guard rawType != nil else {
            logParseFailed(source: source, rawType: rawType, reason: "missingType", keys: keys)
            return nil
        }

        Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=unknown")
        return Result(route: .none, rawType: rawType, keys: keys)
    }

    static func flattenedPayload(from userInfo: [AnyHashable: Any]) -> [String: String] {
        var values: [String: String] = [:]
        flatten(userInfo, into: &values)
        return values
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
        containsAny(["community", "comment", "like", "mention"], in: type)
            || containsAny(["comment", "like", "mention"], in: communityEventValue)
    }

    private static func isOrder(_ type: String) -> Bool {
        containsAny(["order", "order_status", "payment", "review"], in: type)
    }

    private static func containsAny(_ needles: [String], in value: String) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func logParseFailed(source: NotificationRouteSource, rawType: String?, reason: String, keys: [String]) {
        Logger(category: "PushRoute").warning("[PushRoute] parseFailed source=\(source.rawValue) type=\(rawType ?? "unknown") reason=\(reason) keys=\(keys.joined(separator: ","))")
    }
}
