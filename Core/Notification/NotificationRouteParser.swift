import Foundation

enum NotificationRouteSource: String, Equatable, Sendable {
    case remoteFCM
    case localNotification
    case appInternalDebug
    case notificationCenter
}

enum VideoOpenMode: String, Equatable, Sendable {
    case detail
    case shorts
}

enum NotificationRouteIntent: Equatable, Sendable {
    case orderDetail(orderId: String)
    case chatRoom(roomId: String, storeId: String?, opponentId: String?)
    case storeDetail(storeId: String)
    case videoDetail(videoId: String, preferredMode: VideoOpenMode)
    case shorts(videoId: String?)
    case communityPost(postId: String, commentId: String?)
    case cart
    case profile
    case notificationCenter

    var route: AppNotificationRoute {
        switch self {
        case .orderDetail(let orderId):
            return .orderDetail(orderCode: orderId)
        case .chatRoom(let roomId, let storeId, _):
            return .chatRoom(roomId: roomId, storeId: storeId, title: nil)
        case .storeDetail(let storeId):
            return .storeDetail(storeId: storeId)
        case .videoDetail(let videoId, let preferredMode):
            return preferredMode == .shorts ? .shorts(videoId: videoId) : .videoDetail(videoId: videoId)
        case .shorts(let videoId):
            return .shorts(videoId: videoId)
        case .communityPost(let postId, let commentId):
            return .communityPost(postId: postId, commentId: commentId)
        case .cart:
            return .cart
        case .profile:
            return .profile
        case .notificationCenter:
            return .none
        }
    }

    var logName: String {
        switch self {
        case .orderDetail:
            return "orderDetail"
        case .chatRoom:
            return "chatRoom"
        case .storeDetail:
            return "storeDetail"
        case .videoDetail:
            return "videoDetail"
        case .shorts:
            return "shorts"
        case .communityPost:
            return "communityPost"
        case .cart:
            return "cart"
        case .profile:
            return "profile"
        case .notificationCenter:
            return "notificationCenter"
        }
    }
}

struct NotificationRouteParser {
    struct Result: Equatable, Sendable {
        let route: AppNotificationRoute
        let intent: NotificationRouteIntent
        let rawType: String?
        let keys: [String]
    }

    enum ParseResult: Equatable, Sendable {
        case valid(Result)
        case invalid(reason: String, rawType: String?, keys: [String])
        case none(reason: String, rawType: String?, keys: [String])

        var validRoute: Result? {
            if case .valid(let result) = self {
                return result
            }
            return nil
        }

        var route: AppNotificationRoute? {
            validRoute?.route
        }

        var reason: String? {
            switch self {
            case .valid:
                return nil
            case .invalid(let reason, _, _), .none(let reason, _, _):
                return reason
            }
        }
    }

    private static let typeKeys = ["type", "notificationType", "notification_type", "pushType", "push_type", "eventType", "event_type", "event", "category"]
    private static let routeKeys = ["route", "targetRoute", "target_route"]
    private static let chatRoomKeys = ["room_id", "roomId", "chatRoomId", "chat_room_id", "serverRoomId", "server_room_id"]
    private static let storeIdKeys = ["storeId", "store_id"]
    private static let opponentIdKeys = ["opponentId", "opponent_id", "senderId", "sender_id"]
    private static let videoIdKeys = ["videoId", "video_id", "shortsId", "shorts_id", "contentId", "content_id"]
    private static let titleKeys = ["title", "roomTitle", "room_title", "storeName", "store_name"]
    private static let postKeys = ["post_id", "postId", "communityPostId", "community_post_id"]
    private static let commentKeys = ["comment_id", "commentId", "replyId", "reply_id"]
    private static let orderCodeKeys = ["order_code", "orderCode"]
    private static let orderIdKeys = ["order_id", "orderId"]
    private static let communityEventKeys = ["communityEventType", "community_event_type", "eventType", "event_type"]
    private static let messageIdKeys = [
        "chatId",
        "chat_id",
        "messageId",
        "message_id",
        "notification_id",
        "notificationId",
        "gcm.message_id",
        "google.message_id",
        "aps.thread-id",
        "google.c.a.c_id"
    ]

    static func parse(
        userInfo: [AnyHashable: Any],
        source: NotificationRouteSource,
        allowsLocalDebugRoute: Bool = false
    ) -> Result? {
        parseResult(
            rawPayload: flattenedPayload(from: userInfo),
            source: source,
            allowsLocalDebugRoute: allowsLocalDebugRoute
        ).validRoute
    }

    static func parse(
        rawPayload: [String: String],
        source: NotificationRouteSource,
        allowsLocalDebugRoute: Bool = false
    ) -> Result? {
        parseResult(
            rawPayload: rawPayload,
            source: source,
            allowsLocalDebugRoute: allowsLocalDebugRoute
        ).validRoute
    }

    static func parseResult(
        userInfo: [AnyHashable: Any],
        source: NotificationRouteSource,
        allowsLocalDebugRoute: Bool = false
    ) -> ParseResult {
        parseResult(
            rawPayload: flattenedPayload(from: userInfo),
            source: source,
            allowsLocalDebugRoute: allowsLocalDebugRoute
        )
    }

    static func parseResult(
        rawPayload: [String: String],
        source: NotificationRouteSource,
        allowsLocalDebugRoute: Bool = false
    ) -> ParseResult {
        let keys = rawPayload.keys.sorted()
        let rawType = value(for: typeKeys, in: rawPayload)
        let typeValue = normalized(rawType)
        let routeValue = normalized(value(for: routeKeys, in: rawPayload))
        let communityEventValue = normalized(value(for: communityEventKeys, in: rawPayload))
        let keyCount = keys.count

        guard source == .remoteFCM || source == .notificationCenter || allowsLocalDebugRoute else {
            Logger(category: "PushRoute").debug("[PushRoute] ignored source=\(source.rawValue) reason=debugOnly")
            return .none(reason: "unsupportedSource", rawType: rawType, keys: keys)
        }

        Logger(category: "PushDeepLink").debug("[PushDeepLink] parse start source=remote keyCount=\(keyCount)")
        Logger(category: "PushRouteParser").debug("[PushRouteParser] parse start source=\(source.rawValue) keyCount=\(keyCount)")
        Logger(category: "PushRouteParser").debug("[PushRouteParser] customDataKeys=\(customDataKeys(from: keys).joined(separator: ",")) apsKeys=\(apsKeys(from: keys).joined(separator: ","))")

        if let roomMatch = firstValue(for: chatRoomKeys, in: rawPayload) {
            let roomId = roomMatch.value
            if rawType == nil || typeValue == "unknown" {
                Logger(category: "PushPayload").warning("[PushPayload] missingOrUnknownType messageId=\(messageID(from: rawPayload) ?? "unknown") roomIdExists=true action=useRoomIdAsChatRoute")
            }
            let storeId = value(for: storeIdKeys, in: rawPayload)
            let title = value(for: titleKeys, in: rawPayload)
            let intent: NotificationRouteIntent = .chatRoom(
                roomId: roomId,
                storeId: storeId,
                opponentId: value(for: opponentIdKeys, in: rawPayload)
            )
            let route: AppNotificationRoute = .chatRoom(
                roomId: roomId,
                storeId: storeId,
                title: title
            )
            Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=chat requiredIdExists=true")
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=chat roomIdExists=true")
            Logger(category: "PushRouteParser").debug("[PushRouteParser] valid route=chat roomId=\(roomId) storeIdExists=\(storeId != nil) opponentIdExists=\(value(for: opponentIdKeys, in: rawPayload) != nil)")
            Logger(category: "PushRouteParser").debug("[PushRouteParser] valid route=chat roomId=\(roomId) sourceKey=\(roomMatch.key) typeExists=\(rawType != nil)")
            logParsed(intent: intent, valid: true, reason: "ok")
            return .valid(Result(route: route, intent: intent, rawType: rawType, keys: keys))
        }

        if isChat(typeValue) || isChat(routeValue) {
            logParseFailed(source: source, rawType: rawType, reason: "missingChatRoomId", keys: keys, state: .invalid)
            return .invalid(reason: "missingChatRoomId", rawType: rawType, keys: keys)
        }

        if let postId = value(for: postKeys, in: rawPayload) {
            let commentId = value(for: commentKeys, in: rawPayload)
            let result = isCommunityLike(typeValue: typeValue, communityEventValue: communityEventValue) ? "postLike" : "postComment"
            let intent: NotificationRouteIntent = .communityPost(postId: postId, commentId: commentId)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=\(result) requiredIdExists=true")
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=communityPost postIdExists=true commentIdExists=\(commentId != nil)")
            logParsed(intent: intent, valid: true, reason: "ok")
            return .valid(Result(route: intent.route, intent: intent, rawType: rawType, keys: keys))
        }

        if isCommunity(typeValue, communityEventValue: communityEventValue) {
            logParseFailed(source: source, rawType: rawType, reason: "missingPostId", keys: keys, state: .invalid)
            return .invalid(reason: "missingPostId", rawType: rawType, keys: keys)
        }

        if let orderIdentifier = value(for: orderCodeKeys, in: rawPayload) ?? value(for: orderIdKeys, in: rawPayload) {
            let intent: NotificationRouteIntent = .orderDetail(orderId: orderIdentifier)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=order requiredIdExists=true")
            Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=orderDetail orderIdExists=true")
            logParsed(intent: intent, valid: true, reason: "ok")
            return .valid(Result(route: intent.route, intent: intent, rawType: rawType, keys: keys))
        }

        if isOrder(typeValue) {
            logParseFailed(source: source, rawType: rawType, reason: "missingOrderCode", keys: keys, state: .invalid)
            return .invalid(reason: "missingOrderCode", rawType: rawType, keys: keys)
        }

        if let storeId = value(for: storeIdKeys, in: rawPayload),
           containsAny(["store", "shop"], in: typeValue) {
            let intent: NotificationRouteIntent = .storeDetail(storeId: storeId)
            logParsed(intent: intent, valid: true, reason: "ok")
            return .valid(Result(route: intent.route, intent: intent, rawType: rawType, keys: keys))
        }

        if let videoId = value(for: videoIdKeys, in: rawPayload) {
            let intent: NotificationRouteIntent = containsAny(["shorts", "short"], in: typeValue)
                ? .shorts(videoId: videoId)
                : .videoDetail(videoId: videoId, preferredMode: .detail)
            logParsed(intent: intent, valid: true, reason: "ok")
            return .valid(Result(route: intent.route, intent: intent, rawType: rawType, keys: keys))
        }

        if containsAny(["cart"], in: typeValue) {
            let intent: NotificationRouteIntent = .cart
            logParsed(intent: intent, valid: true, reason: "ok")
            return .valid(Result(route: intent.route, intent: intent, rawType: rawType, keys: keys))
        }

        if containsAny(["profile", "user"], in: typeValue) {
            let intent: NotificationRouteIntent = .profile
            logParsed(intent: intent, valid: true, reason: "ok")
            return .valid(Result(route: intent.route, intent: intent, rawType: rawType, keys: keys))
        }

        let reason = hasCustomRoutingData(rawPayload) ? "unknownRoute" : "noCustomData"
        let state: ParseFailureState = hasCustomRoutingData(rawPayload) ? .invalid : .none
        logParseFailed(source: source, rawType: rawType, reason: reason, keys: keys, state: state)
        Logger(category: "PushDeepLink").debug("[PushDeepLink] parse result=notice requiredIdExists=false")
        Logger(category: "PushRoute").debug("[PushRoute] parse source=\(source.rawValue) type=\(rawType ?? "unknown") result=unknown")
        if hasCustomRoutingData(rawPayload) {
            return .invalid(reason: reason, rawType: rawType, keys: keys)
        }
        return .none(reason: reason, rawType: rawType, keys: keys)
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
        firstValue(for: keys, in: payload)?.value
    }

    private static func firstValue(for keys: [String], in payload: [String: String]) -> (key: String, value: String)? {
        for key in keys {
            if let value = payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return (key, value)
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
        let routingKeys = Set(typeKeys + routeKeys + chatRoomKeys + storeIdKeys + opponentIdKeys + videoIdKeys + postKeys + commentKeys + orderCodeKeys + orderIdKeys + communityEventKeys)
        return payload.keys.contains { routingKeys.contains($0) }
    }

    private static func containsAny(_ needles: [String], in value: String) -> Bool {
        needles.contains { value.contains($0) }
    }

    private enum ParseFailureState: Equatable {
        case invalid
        case none
    }

    private static func customDataKeys(from keys: [String]) -> [String] {
        keys.filter { !isDisplayOrProviderKey($0) }
    }

    private static func apsKeys(from keys: [String]) -> [String] {
        keys.filter { key in
            key == "aps"
                || key.hasPrefix("aps.")
                || key == "alert"
                || key.hasPrefix("alert.")
                || ["title", "body", "subtitle", "sound", "badge"].contains(key)
        }
    }

    private static func isDisplayOrProviderKey(_ key: String) -> Bool {
        key == "aps"
            || key.hasPrefix("aps.")
            || key == "alert"
            || key.hasPrefix("alert.")
            || key == "gcm.message_id"
            || key.hasPrefix("google.")
            || ["title", "body", "subtitle", "sound", "badge"].contains(key)
    }

    private static func logParseFailed(source: NotificationRouteSource, rawType: String?, reason: String, keys: [String], state: ParseFailureState) {
        Logger(category: "PushDeepLink").warning("[PushDeepLink] parse failed reason=\(reason) keys=\(keys.joined(separator: ","))")
        Logger(category: "PushRoute").warning("[PushRoute] parseFailed source=\(source.rawValue) type=\(rawType ?? "unknown") reason=\(reason) keys=\(keys.joined(separator: ","))")
        Logger(category: "PushRouteParser").warning("[PushRouteParser] invalid reason=\(reason) type=\(rawType ?? "unknown") keys=\(keys.joined(separator: ","))")
        let routeName = state == .none ? "none" : "invalid"
        Logger(category: "PushRouteParser").debug("[PushRouteParser] parsed route=\(routeName) valid=false reason=\(reason)")
    }

    private static func logParsed(intent: NotificationRouteIntent, valid: Bool, reason: String) {
        Logger(category: "PushRouteParser").debug("[PushRouteParser] parsed route=\(intent.logName) valid=\(valid) reason=\(reason)")
    }
}
