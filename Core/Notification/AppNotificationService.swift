import Foundation
import UIKit
import UserNotifications

enum PushNotificationLifecycle: String, Sendable {
    case launchOptions
    case didReceiveRemoteNotification
    case willPresent
    case didReceive
}

struct PushNotificationEvent: Sendable {
    let rawPayload: [String: String]
    let parsedRoute: AppNotificationRoute?
    let routeParseResult: NotificationRouteParser.ParseResult
    let messageId: String?
    let actionIdentifier: String?
    let lifecycle: PushNotificationLifecycle
    let source: NotificationRouteSource
    let isTap: Bool

    var logMessageId: String {
        messageId ?? "unknown"
    }

    init(
        rawPayload: [String: String],
        parsedRoute: AppNotificationRoute?,
        routeParseResult: NotificationRouteParser.ParseResult? = nil,
        messageId: String?,
        actionIdentifier: String?,
        lifecycle: PushNotificationLifecycle,
        source: NotificationRouteSource,
        isTap: Bool
    ) {
        let parseResult = routeParseResult ?? NotificationRouteParser.parseResult(rawPayload: rawPayload, source: source)
        self.rawPayload = rawPayload
        self.routeParseResult = parseResult
        self.parsedRoute = parsedRoute ?? parseResult.route
        self.messageId = messageId
        self.actionIdentifier = actionIdentifier
        self.lifecycle = lifecycle
        self.source = source
        self.isTap = isTap
    }
}

enum PushNotificationEventFactory {
    static func makeEvent(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String?,
        lifecycle: PushNotificationLifecycle,
        source: NotificationRouteSource,
        isTap: Bool
    ) -> PushNotificationEvent {
        makeEvent(
            rawPayload: NotificationRouteParser.flattenedPayload(from: userInfo),
            actionIdentifier: actionIdentifier,
            lifecycle: lifecycle,
            source: source,
            isTap: isTap
        )
    }

    static func makeEvent(
        rawPayload: [String: String],
        actionIdentifier: String?,
        lifecycle: PushNotificationLifecycle,
        source: NotificationRouteSource,
        isTap: Bool
    ) -> PushNotificationEvent {
        let parseResult = NotificationRouteParser.parseResult(rawPayload: rawPayload, source: source)
        return PushNotificationEvent(
            rawPayload: rawPayload,
            parsedRoute: parseResult.route,
            routeParseResult: parseResult,
            messageId: NotificationRouteParser.messageID(from: rawPayload),
            actionIdentifier: actionIdentifier,
            lifecycle: lifecycle,
            source: source,
            isTap: isTap
        )
    }
}

@MainActor
protocol AppNotificationService: AnyObject {
    var unreadCountChanged: ((Int) -> Void)? { get set }
    var notificationReceived: ((AppNotification) -> Void)? { get set }

    func handleRemoteNotificationPayload(_ userInfo: [AnyHashable: Any])
    func handleRemoteNotificationPayload(_ rawPayload: [String: String])
    func handlePushNotificationEvent(_ event: PushNotificationEvent)
    func handleRemoteNotificationTapPayload(_ userInfo: [AnyHashable: Any])
    func handleRemoteNotificationTapPayload(_ rawPayload: [String: String])
    func handleRemoteNotificationTapPayload(_ rawPayload: [String: String], parsedRoute: AppNotificationRoute?, messageId: String?, source: NotificationRouteSource)
    func shouldSuppressForegroundBanner(for userInfo: [AnyHashable: Any]) -> Bool
    func shouldSuppressForegroundBanner(for rawPayload: [String: String]) -> Bool
    @discardableResult func handleOrderStatusChanged(orderCode: String, previousStatus: String?, currentStatus: String, storeName: String?) -> AppNotificationSaveResult
    @discardableResult func handleChatMessageReceived(roomId: String, storeId: String?, title: String?, messageId: String?, senderId: String?, preview: String) -> AppNotificationSaveResult
    @discardableResult func handleCommunityComment(postId: String, commentId: String?, actorUserId: String?, actorName: String?, preview: String?) -> AppNotificationSaveResult
    @discardableResult func handleCommunityLike(postId: String, commentId: String?, actorUserId: String?, actorName: String?) -> AppNotificationSaveResult
    @discardableResult func handleCommunityMention(postId: String, commentId: String?, actorUserId: String?, actorName: String?, preview: String?) -> AppNotificationSaveResult
    func markAsRead(id: String)
    func markAllAsRead()
    func deleteNotification(id: String)
    func deleteAll()
    func fetchNotifications() -> [AppNotification]
    func unreadCount() -> Int
}

struct ChatNotificationIdentity: Equatable, Hashable, Sendable {
    let rawValue: String
    let providerMessageId: String?
    let chatMessageId: String?
    let roomId: String?
    let senderId: String?
    let createdAt: String?
    let bodyHash: String?
    let missingFields: [String]
    let strategy: String
}

@MainActor
final class DefaultAppNotificationService: AppNotificationService {
    var unreadCountChanged: ((Int) -> Void)?
    var notificationReceived: ((AppNotification) -> Void)?
    var currentUserIDProvider: (() -> String?)?

    private let repository: AppNotificationRepository
    private let router: AppNotificationRouting
    private let activeChatRoomTracker: ActiveChatRoomTracking
    private let activeCommunityPostTracker: ActiveCommunityPostTracking
    private let diagnosticsStore: NotificationDiagnosticsStore
    private let dedupeStore: PushNotificationDedupeStore
    private let visibleDedupeStore: VisibleNotificationDedupeStore

    init(
        repository: AppNotificationRepository,
        router: AppNotificationRouting,
        activeChatRoomTracker: ActiveChatRoomTracking,
        activeCommunityPostTracker: ActiveCommunityPostTracking,
        diagnosticsStore: NotificationDiagnosticsStore,
        dedupeStore: PushNotificationDedupeStore = PushNotificationDedupeStore(),
        visibleDedupeStore: VisibleNotificationDedupeStore = VisibleNotificationDedupeStore()
    ) {
        self.repository = repository
        self.router = router
        self.activeChatRoomTracker = activeChatRoomTracker
        self.activeCommunityPostTracker = activeCommunityPostTracker
        self.diagnosticsStore = diagnosticsStore
        self.dedupeStore = dedupeStore
        self.visibleDedupeStore = visibleDedupeStore
    }

    func handleRemoteNotificationPayload(_ userInfo: [AnyHashable: Any]) {
        handleRemoteNotificationPayload(RemoteNotificationPayload(userInfo: userInfo).rawPayload)
    }

    func handleRemoteNotificationPayload(_ rawPayload: [String: String]) {
        handlePushNotificationEvent(PushNotificationEventFactory.makeEvent(
            rawPayload: rawPayload,
            actionIdentifier: nil,
            lifecycle: .didReceiveRemoteNotification,
            source: .remoteFCM,
            isTap: false
        ))
    }

    func handlePushNotificationEvent(_ event: PushNotificationEvent) {
        let rawPayload = event.rawPayload
        let payload = RemoteNotificationPayload(rawPayload: rawPayload)
        diagnosticsStore.recordRemotePayload(payload.rawPayload)
        Logger(category: "RemotePush").debug("[RemotePush] received payload keys=\(payload.rawPayload.keys.sorted().joined(separator: ",")) messageId=\(payload.messageID) type=\(payload.type ?? "unknown") source=\(payload.source ?? "unknown")")
        let normalizedMessageId = event.messageId ?? payload.messageID.nilIfUnknown
        var routeForNavigation: AppNotificationRoute?
        let appStateLogValue = UIApplication.shared.applicationState.notificationLogValue
        let validParsedRoute = event.routeParseResult.route
        _ = dedupeStore.accept(
            key: "receive:\(notificationDedupeKey(rawPayload: rawPayload, route: validParsedRoute, messageId: normalizedMessageId))",
            source: event.source.rawValue,
            phase: .receive
        )

        switch event.lifecycle {
        case .willPresent:
            Logger(category: "PushLifecycle").debug("[PushLifecycle] willPresent messageId=\(normalizedMessageId ?? "unknown") action=saveAndPresentBanner")
            Logger(category: "PushLifecycle").debug("[PushLifecycle] navigationSkipped reason=willPresentDoesNotNavigate messageId=\(normalizedMessageId ?? "unknown")")
        case .didReceive:
            Logger(category: "PushLifecycle").debug("[PushLifecycle] didReceive messageId=\(normalizedMessageId ?? "unknown") appState=\(appStateLogValue) action=navigate")
        case .launchOptions:
            Logger(category: "PushLifecycle").debug("[PushLifecycle] coldStart messageId=\(normalizedMessageId ?? "unknown") action=storePending")
        case .didReceiveRemoteNotification:
            break
        }

        if let notification = makeNotification(from: payload, parsedRoute: validParsedRoute) {
            if event.lifecycle == .willPresent,
               notification.type == .chatMessage,
               notification.metadata.roomId == activeChatRoomTracker.activeRoomId {
                Logger(category: "Notification").debug("[Notification] skipped id=\(notification.id) type=\(notification.type.rawValue) reason=activeChatRoom source=\(event.source.rawValue)")
            } else {
                saveIfNeeded(notification, source: event.source.rawValue, messageId: normalizedMessageId, rawPayload: payload.rawPayload)
            }
            if event.isTap {
                if notification.type == .chatMessage {
                    Logger(category: "ChatRead").debug("[ChatRead] roomScopeKey=\(chatRoomScopeKey(roomId: notification.metadata.roomId, storeId: notification.metadata.storeId)) action=skip reason=navigationNotVisibleYet")
                } else {
                    markAsReadIfNeeded(id: notification.id, messageId: normalizedMessageId)
                }
                diagnosticsStore.recordRemoteTapRoute(notification.route.debugDescription, pendingRoute: nil)
            }
            if let validParsedRoute {
                routeForNavigation = validParsedRoute
            } else if notification.route != .none {
                routeForNavigation = notification.route
            }
        } else if let parsedRoute = validParsedRoute, parsedRoute != .none {
            if event.isTap {
                diagnosticsStore.recordRemoteTapRoute(parsedRoute.debugDescription, pendingRoute: nil)
            }
            routeForNavigation = parsedRoute
        } else {
            if event.isTap {
                diagnosticsStore.recordRemoteTapRoute(AppNotificationRoute.none.debugDescription, pendingRoute: nil)
            }
            Logger(category: "Push").warning("[Push] missingRoutePayload keys=\(payload.rawPayload.keys.sorted().joined(separator: ","))")
            routeForNavigation = nil
        }

        guard event.isTap else { return }
        guard let routeForNavigation else {
            let reason = event.routeParseResult.reason ?? "invalidRoute"
            Logger(category: "PushDeepLink").warning("[PushDeepLink] navigation skipped reason=invalidRoute messageId=\(normalizedMessageId ?? "unknown") parseReason=\(reason)")
            return
        }
        router.handleNotificationTap(
            route: routeForNavigation,
            messageId: normalizedMessageId,
            source: event.source
        )
    }

    func handleRemoteNotificationTapPayload(_ userInfo: [AnyHashable: Any]) {
        handleRemoteNotificationTapPayload(RemoteNotificationPayload(userInfo: userInfo).rawPayload)
    }

    func handleRemoteNotificationTapPayload(_ rawPayload: [String: String]) {
        handlePushNotificationEvent(PushNotificationEventFactory.makeEvent(
            rawPayload: rawPayload,
            actionIdentifier: nil,
            lifecycle: .didReceive,
            source: .remoteFCM,
            isTap: true
        ))
    }

    func handleRemoteNotificationTapPayload(
        _ rawPayload: [String: String],
        parsedRoute: AppNotificationRoute?,
        messageId: String?,
        source: NotificationRouteSource
    ) {
        handlePushNotificationEvent(PushNotificationEvent(
            rawPayload: rawPayload,
            parsedRoute: parsedRoute,
            routeParseResult: NotificationRouteParser.parseResult(rawPayload: rawPayload, source: source),
            messageId: messageId?.nilIfUnknown,
            actionIdentifier: nil,
            lifecycle: .didReceive,
            source: source,
            isTap: true
        ))
    }

    func shouldSuppressForegroundBanner(for userInfo: [AnyHashable: Any]) -> Bool {
        shouldSuppressForegroundBanner(for: RemoteNotificationPayload(userInfo: userInfo).rawPayload)
    }

    func shouldSuppressForegroundBanner(for rawPayload: [String: String]) -> Bool {
        let payload = RemoteNotificationPayload(rawPayload: rawPayload)
        let parsedRoute = NotificationRouteParser.parse(rawPayload: rawPayload, source: .remoteFCM)?.route
        let identity = notificationDedupeKey(rawPayload: rawPayload, route: parsedRoute, messageId: payload.messageID.nilIfUnknown)
        let displayAccepted = visibleDedupeStore.accept(identity: identity, source: "remoteFCM")
        logNotificationIdentity(rawPayload: rawPayload, route: parsedRoute, messageId: payload.messageID.nilIfUnknown, source: "remoteFCM", action: displayAccepted ? "displayAllowed" : "displaySuppressed")
        guard displayAccepted else {
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner suppressed source=remoteFCM reason=duplicate identity=\(identity)")
            return true
        }

        if let roomId = payload.string(for: RemoteNotificationPayload.chatRoomKeys),
           activeChatRoomTracker.activeRoomId == roomId {
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] willPresent messageId=\(payload.messageID) roomId=\(roomId) currentRoomId=\(activeChatRoomTracker.activeRoomId ?? "-") decision=suppress reason=alreadyInSameChat")
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] suppressed reason=alreadyInSameChat roomId=\(roomId)")
            return true
        }

        if let roomId = payload.string(for: RemoteNotificationPayload.chatRoomKeys) {
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] willPresent messageId=\(payload.messageID) roomId=\(roomId) currentRoomId=\(activeChatRoomTracker.activeRoomId ?? "-") decision=banner reason=differentOrNoActiveChat")
        }

        if payload.isCommunityEvent,
           let postId = payload.string(for: RemoteNotificationPayload.postKeys),
           activeCommunityPostTracker.activePostId == postId,
           !payload.isCommunityMention {
            Logger(category: "NotificationPresentation").debug("[NotificationPresentation] foreground banner suppressed source=remoteFCM reason=activePost postId=\(postId)")
            return true
        }

        return false
    }

    @discardableResult
    func handleOrderStatusChanged(orderCode: String, previousStatus: String?, currentStatus: String, storeName: String?) -> AppNotificationSaveResult {
        let normalizedOrderCode = orderCode.trimmed
        let normalizedStatus = currentStatus.trimmed
        guard !normalizedOrderCode.isEmpty, !normalizedStatus.isEmpty else {
            return logSkippedNotification(id: "-", type: .orderStatus, reason: "invalidPayload", source: "appInternalDebug")
        }
        guard previousStatus?.trimmed != normalizedStatus else {
            let id = Self.stableID(parts: ["order", normalizedOrderCode, normalizedStatus])
            return logSkippedNotification(id: id, type: .orderStatus, reason: "unchangedStatus", source: "appInternalDebug")
        }

        let id = Self.stableID(parts: ["order", normalizedOrderCode, normalizedStatus])
        let statusText = orderStatusDisplayText(normalizedStatus)
        let bodyPrefix = storeName?.trimmed.nilIfEmpty.map { "\($0) 주문이" } ?? "주문이"
        let notification = AppNotification(
            id: id,
            type: normalizedStatus.caseInsensitiveCompare("PAID") == .orderedSame ? .payment : .orderStatus,
            title: normalizedStatus.caseInsensitiveCompare("PICKED_UP") == .orderedSame ? "리뷰를 작성할 수 있어요" : "주문 상태가 변경되었어요",
            body: "\(bodyPrefix) \(statusText) 상태로 변경되었어요.",
            createdAt: Date(),
            readState: .unread,
            route: .orderDetail(orderCode: normalizedOrderCode),
            metadata: AppNotificationMetadata(orderCode: normalizedOrderCode, orderStatus: normalizedStatus)
        )

        Logger(category: "OrderNotification").debug("[OrderNotification] status changed orderCode=\(normalizedOrderCode) previous=\(previousStatus ?? "nil") current=\(normalizedStatus)")
        return save(notification, source: "appInternalDebug")
    }

    @discardableResult
    func handleChatMessageReceived(roomId: String, storeId: String?, title: String?, messageId: String?, senderId: String?, preview: String) -> AppNotificationSaveResult {
        let normalizedRoomId = roomId.trimmed
        guard !normalizedRoomId.isEmpty else {
            return logSkippedNotification(id: "-", type: .chatMessage, reason: "invalidPayload", source: "appInternalDebug")
        }
        guard activeChatRoomTracker.activeRoomId != normalizedRoomId else {
            let id = messageId?.trimmed.nilIfEmpty ?? Self.stableID(parts: ["chat", normalizedRoomId, senderId?.trimmed ?? "-", preview.trimmed, Self.timeBucket()])
            return logSkippedNotification(id: id, type: .chatMessage, reason: "activeChatRoom", source: "appInternalDebug")
        }
        if let currentUserID = currentUserIDProvider?(), senderId?.trimmed == currentUserID {
            let id = messageId?.trimmed.nilIfEmpty ?? Self.stableID(parts: ["chat", normalizedRoomId, senderId?.trimmed ?? "-", preview.trimmed, Self.timeBucket()])
            return logSkippedNotification(id: id, type: .chatMessage, reason: "ownAction", source: "appInternalDebug")
        }

        let normalizedMessageId = messageId?.trimmed.nilIfEmpty
        let identity = Self.chatNotificationIdentity(
            rawPayload: nil,
            route: .chatRoom(roomId: normalizedRoomId, storeId: storeId?.trimmed.nilIfEmpty, title: title?.trimmed.nilIfEmpty),
            messageId: normalizedMessageId,
            senderId: senderId,
            preview: preview
        )
        let id = identity.rawValue
        let displayTitle = title?.trimmed.nilIfEmpty ?? "새 채팅 메시지"
        let body = preview.trimmed.nilIfEmpty ?? "\(displayTitle)에서 새 메시지가 도착했어요."
        let notification = AppNotification(
            id: id,
            type: .chatMessage,
            title: "새 채팅 메시지",
            body: body,
            createdAt: Date(),
            readState: .unread,
            route: .chatRoom(roomId: normalizedRoomId, storeId: storeId?.trimmed.nilIfEmpty, title: displayTitle),
            metadata: AppNotificationMetadata(roomId: normalizedRoomId, storeId: storeId?.trimmed.nilIfEmpty, messageId: normalizedMessageId, senderId: senderId?.trimmed.nilIfEmpty)
        )
        logNotificationIdentity(identity, source: "socket", action: "socketReceive")
        Logger(category: "LocalNotification").debug("[LocalNotification] scheduleAttempt type=chat messageId=\(normalizedMessageId ?? "unknown") roomId=\(normalizedRoomId)")
        let result = saveIfNeeded(notification, source: "socket", messageId: normalizedMessageId, rawPayload: nil)
        if case .duplicate = result {
            Logger(category: "LocalNotification").debug("[LocalNotification] scheduleSkipped reason=remotePushAlreadyHandled messageId=\(normalizedMessageId ?? "unknown")")
        }
        return result
    }

    @discardableResult
    func handleCommunityComment(postId: String, commentId: String?, actorUserId: String?, actorName: String?, preview: String?) -> AppNotificationSaveResult {
        return saveCommunityNotification(
            type: .communityComment,
            postId: postId,
            commentId: commentId,
            actorUserId: actorUserId,
            actorName: actorName,
            eventType: "comment",
            title: "새 댓글이 달렸어요",
            fallbackBody: "내 게시글에 새로운 댓글이 달렸어요.",
            preview: preview
        )
    }

    @discardableResult
    func handleCommunityLike(postId: String, commentId: String?, actorUserId: String?, actorName: String?) -> AppNotificationSaveResult {
        let target = commentId?.trimmed.nilIfEmpty == nil ? "게시글" : "댓글"
        let actorText = actorName?.trimmed.nilIfEmpty.map { "\($0)님이 " } ?? ""
        return saveCommunityNotification(
            type: .communityLike,
            postId: postId,
            commentId: commentId,
            actorUserId: actorUserId,
            actorName: actorName,
            eventType: "like",
            title: "\(target)에 좋아요가 눌렸어요",
            fallbackBody: "\(actorText)내 \(target)을 좋아합니다.",
            preview: nil
        )
    }

    @discardableResult
    func handleCommunityMention(postId: String, commentId: String?, actorUserId: String?, actorName: String?, preview: String?) -> AppNotificationSaveResult {
        let actorText = actorName?.trimmed.nilIfEmpty.map { "\($0)님이 " } ?? ""
        return saveCommunityNotification(
            type: .communityMention,
            postId: postId,
            commentId: commentId,
            actorUserId: actorUserId,
            actorName: actorName,
            eventType: "mention",
            title: "댓글에서 나를 언급했어요",
            fallbackBody: "\(actorText)댓글에서 나를 언급했어요.",
            preview: preview
        )
    }

    func markAsRead(id: String) {
        repository.markAsRead(id: id)
        let count = publishUnreadCount()
        Logger(category: "Notification").debug("[Notification] markAsRead id=\(id) unreadCount=\(count)")
    }

    func markAllAsRead() {
        repository.markAllAsRead()
        let count = publishUnreadCount()
        Logger(category: "Notification").debug("[Notification] markAllAsRead unreadCount=\(count)")
    }

    func deleteNotification(id: String) {
        repository.deleteNotification(id: id)
        publishUnreadCount()
    }

    func deleteAll() {
        repository.deleteAll()
        publishUnreadCount()
    }

    func fetchNotifications() -> [AppNotification] {
        repository.fetchNotifications()
    }

    func unreadCount() -> Int {
        repository.unreadCount()
    }

    private func makeNotification(from payload: RemoteNotificationPayload, parsedRoute: AppNotificationRoute? = nil) -> AppNotification? {
        let route = parsedRoute ?? NotificationRouteParser.parse(rawPayload: payload.rawPayload, source: .remoteFCM)?.route
        switch route {
        case .chatRoom(let roomId, _, _):
            return payload.chatNotification(roomId: roomId)
        case .orderDetail(let orderCode):
            return payload.orderNotification(orderCode: orderCode)
        case .communityPost(let postId, _):
            if payload.isCommunityLike {
                return payload.communityNotification(postId: postId, type: .communityLike, eventType: "like")
            }
            if payload.isCommunityMention {
                return payload.communityNotification(postId: postId, type: .communityMention, eventType: "mention")
            }
            return payload.communityNotification(postId: postId, type: .communityComment, eventType: "comment")
        default:
            break
        }
        guard payload.title != nil || payload.body != nil else { return nil }
        return payload.systemNotification()
    }

    @discardableResult
    private func saveIfNeeded(_ notification: AppNotification, source: String, messageId: String?, rawPayload: [String: String]?) -> AppNotificationSaveResult {
        let key = "notification:\(notificationDedupeKey(rawPayload: rawPayload, route: notification.route, messageId: messageId ?? notification.metadata.messageId ?? notification.id))"
        Logger(category: "Notification").debug("[Notification] saveAttempt id=\(notification.id) type=\(notification.type.rawValue) roomId=\(notification.metadata.roomId ?? "-") source=\(source)")
        logNotificationIdentity(rawPayload: rawPayload, route: notification.route, messageId: messageId ?? notification.metadata.messageId ?? notification.id, source: source, action: "saveAttempt")
        guard dedupeStore.accept(key: key, source: source, phase: .save) else {
            Logger(category: "Notification").debug("[Notification] saveSkipped reason=duplicate id=\(notification.id)")
            return .duplicate(id: notification.id)
        }
        return save(notification, source: source)
    }

    private func markAsReadIfNeeded(id: String, messageId: String?) {
        let key = "read:\(messageId?.trimmed.nilIfEmpty ?? id)"
        guard dedupeStore.accept(key: key, source: "remoteFCM", phase: .read) else { return }
        markAsRead(id: id)
    }

    private func chatRoomScopeKey(roomId: String?, storeId: String?) -> String {
        "store:\(storeId?.trimmed.nilIfEmpty ?? "-")|room:\(roomId?.trimmed.nilIfEmpty ?? "-")"
    }

    private func notificationDedupeKey(rawPayload: [String: String]?, route: AppNotificationRoute?, messageId: String?) -> String {
        if let identity = Self.chatNotificationIdentityIfPossible(rawPayload: rawPayload, route: route, messageId: messageId) {
            return identity.rawValue
        }
        let providerMessageId = Self.firstValue(for: ["gcm.message_id", "google.message_id", "google.c.a.c_id"], in: rawPayload)?.trimmed.nilIfEmpty
        if let notificationId = Self.firstValue(for: ["notification_id", "notificationId", "id"], in: rawPayload)?.trimmed.nilIfEmpty {
            return "notificationId:\(notificationId)"
        }
        if let messageId = messageId?.trimmed.nilIfEmpty, messageId != "unknown" {
            return "messageId:\(messageId)"
        }
        if let providerMessageId {
            return "providerMessageId:\(providerMessageId)"
        }
        return "notificationId:unknown"
    }

    private func logNotificationIdentity(rawPayload: [String: String]?, route: AppNotificationRoute?, messageId: String?, source: String, action: String) {
        if let identity = Self.chatNotificationIdentityIfPossible(rawPayload: rawPayload, route: route, messageId: messageId) {
            logNotificationIdentity(identity, source: source, action: action)
        }
    }

    private func logNotificationIdentity(_ identity: ChatNotificationIdentity, source: String, action: String) {
        Logger(category: "NotificationIdentity").debug(
            "[NotificationIdentity] stableIdentity=\(identity.rawValue) providerMessageId=\(identity.providerMessageId ?? "nil") chatId=\(identity.chatMessageId ?? "nil") roomId=\(identity.roomId ?? "nil") senderId=\(identity.senderId ?? "nil") createdAt=\(identity.createdAt ?? "nil") bodyHash=\(identity.bodyHash ?? "nil") source=\(source) strategy=\(identity.strategy) missingFields=\(identity.missingFields.joined(separator: ",")) action=\(action)"
        )
    }

    nonisolated static func chatNotificationIdentityIfPossible(
        rawPayload: [String: String]?,
        route: AppNotificationRoute?,
        messageId: String?
    ) -> ChatNotificationIdentity? {
        guard route?.chatRoomId != nil
            || firstValue(for: RemoteNotificationPayload.chatRoomKeys, in: rawPayload)?.trimmed.nilIfEmpty != nil
            || firstValue(for: ["chatId", "chat_id", "messageId", "message_id"], in: rawPayload)?.trimmed.nilIfEmpty != nil
        else {
            return nil
        }
        return chatNotificationIdentity(rawPayload: rawPayload, route: route, messageId: messageId, senderId: nil, preview: nil)
    }

    nonisolated static func chatNotificationIdentity(
        rawPayload: [String: String]?,
        route: AppNotificationRoute?,
        messageId: String?,
        senderId explicitSenderId: String?,
        preview explicitPreview: String?
    ) -> ChatNotificationIdentity {
        let providerMessageId = firstValue(for: ["gcm.message_id", "google.message_id", "google.c.a.c_id"], in: rawPayload)?.trimmed.nilIfEmpty
        let chatMessageId = firstValue(for: ["chatId", "chat_id", "messageId", "message_id"], in: rawPayload)?.trimmed.nilIfEmpty
            ?? (rawPayload == nil ? messageId?.trimmed.nilIfEmpty : nil)
        let roomId = route?.chatRoomId?.trimmed.nilIfEmpty
            ?? firstValue(for: RemoteNotificationPayload.chatRoomKeys, in: rawPayload)?.trimmed.nilIfEmpty
        let senderId = explicitSenderId?.trimmed.nilIfEmpty
            ?? firstValue(for: RemoteNotificationPayload.senderIdKeys, in: rawPayload)?.trimmed.nilIfEmpty
        let createdAt = firstValue(for: ["createdAt", "created_at", "sentAt", "sent_at", "timestamp"], in: rawPayload)?.trimmed.nilIfEmpty
        let preview = explicitPreview?.trimmed.nilIfEmpty
            ?? firstValue(for: RemoteNotificationPayload.previewKeys, in: rawPayload)?.trimmed.nilIfEmpty
        let bodyHash = preview.map { stableHash(parts: [$0.normalizedNotificationBody]) }
        let missingFields = [
            roomId == nil ? "roomId" : nil,
            senderId == nil ? "senderId" : nil,
            createdAt == nil ? "createdAt" : nil,
            preview == nil ? "body" : nil
        ].compactMap { $0 }

        if let chatMessageId, chatMessageId != "unknown" {
            return ChatNotificationIdentity(
                rawValue: "chatMessageId:\(chatMessageId)",
                providerMessageId: providerMessageId,
                chatMessageId: chatMessageId,
                roomId: roomId,
                senderId: senderId,
                createdAt: createdAt,
                bodyHash: bodyHash,
                missingFields: missingFields,
                strategy: "chatMessageId"
            )
        }
        if let roomId, let senderId, let createdAt, let bodyHash {
            return ChatNotificationIdentity(
                rawValue: "chatFallback:\(roomId):\(senderId):\(createdAt):\(bodyHash)",
                providerMessageId: providerMessageId,
                chatMessageId: nil,
                roomId: roomId,
                senderId: senderId,
                createdAt: createdAt,
                bodyHash: bodyHash,
                missingFields: missingFields,
                strategy: "roomSenderCreatedBody"
            )
        }
        if let roomId, let bodyHash {
            let bucket = roundedCreatedAtWindow(from: createdAt)
            return ChatNotificationIdentity(
                rawValue: "chatFallback:\(roomId):body:\(bucket):\(bodyHash)",
                providerMessageId: providerMessageId,
                chatMessageId: nil,
                roomId: roomId,
                senderId: senderId,
                createdAt: createdAt,
                bodyHash: bodyHash,
                missingFields: missingFields,
                strategy: "roomBodyWindow"
            )
        }
        if let roomId {
            let bucket = roundedCreatedAtWindow(from: createdAt)
            return ChatNotificationIdentity(
                rawValue: "chatFallback:\(roomId):window:\(bucket)",
                providerMessageId: providerMessageId,
                chatMessageId: nil,
                roomId: roomId,
                senderId: senderId,
                createdAt: createdAt,
                bodyHash: bodyHash,
                missingFields: missingFields,
                strategy: "roomWindow"
            )
        }
        return ChatNotificationIdentity(
            rawValue: "providerMessageId:\(providerMessageId ?? "unknown")",
            providerMessageId: providerMessageId,
            chatMessageId: nil,
            roomId: nil,
            senderId: senderId,
            createdAt: createdAt,
            bodyHash: bodyHash,
            missingFields: missingFields,
            strategy: "providerMessageIdLastFallback"
        )
    }

    nonisolated private static func roundedCreatedAtWindow(from createdAt: String?) -> String {
        if let createdAt,
           let seconds = Double(createdAt) {
            return String(Int(seconds / 30))
        }
        return timeBucket(interval: 30)
    }

    nonisolated private static func firstValue(for keys: [String], in payload: [String: String]?) -> String? {
        guard let payload else { return nil }
        for key in keys {
            if let value = payload[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    @discardableResult
    private func saveCommunityNotification(
        type: AppNotificationType,
        postId: String,
        commentId: String?,
        actorUserId: String?,
        actorName: String?,
        eventType: String,
        title: String,
        fallbackBody: String,
        preview: String?
    ) -> AppNotificationSaveResult {
        let normalizedPostId = postId.trimmed
        let normalizedCommentId = commentId?.trimmed.nilIfEmpty
        let normalizedActorUserId = actorUserId?.trimmed.nilIfEmpty
        let id = Self.stableID(parts: ["community", normalizedPostId, normalizedCommentId ?? "-", normalizedActorUserId ?? "-", eventType])

        Logger(category: "CommunityNotification").debug("[CommunityNotification] \(eventType) detected postId=\(normalizedPostId.isEmpty ? "-" : normalizedPostId) commentId=\(normalizedCommentId ?? "-") actorUserId=\(normalizedActorUserId ?? "-") source=appInternalDebug")

        guard !normalizedPostId.isEmpty else {
            return logSkippedNotification(id: "-", type: type, reason: "invalidPayload", source: "appInternalDebug")
        }
        if let currentUserID = currentUserIDProvider?(),
           normalizedActorUserId == currentUserID {
            return logSkippedNotification(id: id, type: type, reason: "ownAction", source: "appInternalDebug")
        }
        if activeCommunityPostTracker.activePostId == normalizedPostId, type != .communityMention {
            return logSkippedNotification(id: id, type: type, reason: "activePost", source: "appInternalDebug")
        }

        let notification = AppNotification(
            id: id,
            type: type,
            title: title,
            body: preview?.trimmed.nilIfEmpty ?? fallbackBody,
            createdAt: Date(),
            readState: .unread,
            route: .communityPost(postId: normalizedPostId, commentId: normalizedCommentId),
            metadata: AppNotificationMetadata(postId: normalizedPostId, commentId: normalizedCommentId, actorUserId: normalizedActorUserId, communityEventType: eventType)
        )
        return save(notification, source: "appInternalDebug")
    }

    @discardableResult
    private func save(_ notification: AppNotification, source: String) -> AppNotificationSaveResult {
        let result = repository.saveNotification(notification)
        switch result {
        case .saved(let unreadCount):
            Logger(category: "Notification").debug("[Notification] saved id=\(notification.id) type=\(notification.type.rawValue) unreadCount=\(unreadCount) source=\(source)")
            notificationReceived?(notification)
            publishUnreadCount()
        case .duplicate:
            Logger(category: "Notification").debug("[Notification] duplicate skipped id=\(notification.id) type=\(notification.type.rawValue) reason=existingId source=\(source)")
        case .skipped(let reason):
            Logger(category: "Notification").debug("[Notification] skipped id=\(notification.id) type=\(notification.type.rawValue) reason=\(reason) source=\(source)")
        case .failed(let reason):
            Logger(category: "Notification").warning("[Notification] failed id=\(notification.id) type=\(notification.type.rawValue) reason=\(reason) source=\(source)")
        }
        return result
    }

    @discardableResult
    private func logSkippedNotification(id: String, type: AppNotificationType, reason: String, source: String) -> AppNotificationSaveResult {
        Logger(category: "Notification").debug("[Notification] skipped id=\(id) type=\(type.rawValue) reason=\(reason) source=\(source)")
        return .skipped(reason: reason)
    }

    @discardableResult
    private func publishUnreadCount() -> Int {
        let count = repository.unreadCount()
        unreadCountChanged?(count)
        NotificationCenter.default.post(
            name: .pikkoAppNotificationUnreadCountDidChange,
            object: nil,
            userInfo: [AppNotificationUserInfoKey.unreadCount: count]
        )
        UNUserNotificationCenter.current().setBadgeCount(count)
        return count
    }

    private func orderStatusDisplayText(_ status: String) -> String {
        switch status.uppercased() {
        case "PAID", "PAYMENT_COMPLETED":
            return "결제 완료"
        case "APPROVED", "ACCEPTED":
            return "주문 승인"
        case "COOKING", "PREPARING":
            return "조리중"
        case "READY", "PICKUP_READY":
            return "픽업대기"
        case "PICKED_UP", "COMPLETED":
            return "픽업완료"
        case "CANCELLED", "CANCELED", "REJECTED":
            return "주문 취소"
        default:
            return status
        }
    }

    nonisolated static func stableID(parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
    }

    nonisolated static func timeBucket(date: Date = Date(), interval: TimeInterval = 60) -> String {
        String(Int(date.timeIntervalSince1970 / interval))
    }

    nonisolated static func stableHash(parts: [String]) -> String {
        let text = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private extension UIApplication.State {
    var notificationLogValue: String {
        switch self {
        case .active:
            return "foreground"
        case .background:
            return "background"
        case .inactive:
            return "inactive"
        @unknown default:
            return "unknown"
        }
    }
}

enum AppNotificationUserInfoKey {
    static let unreadCount = "unreadCount"
}

extension Notification.Name {
    static let pikkoAppNotificationUnreadCountDidChange = Notification.Name("pikkoAppNotificationUnreadCountDidChange")
}

@MainActor
final class NoopAppNotificationService: AppNotificationService {
    var unreadCountChanged: ((Int) -> Void)?
    var notificationReceived: ((AppNotification) -> Void)?

    func handleRemoteNotificationPayload(_ userInfo: [AnyHashable: Any]) {}
    func handleRemoteNotificationPayload(_ rawPayload: [String: String]) {}
    func handlePushNotificationEvent(_ event: PushNotificationEvent) {}
    func handleRemoteNotificationTapPayload(_ userInfo: [AnyHashable: Any]) {}
    func handleRemoteNotificationTapPayload(_ rawPayload: [String: String]) {}
    func handleRemoteNotificationTapPayload(_ rawPayload: [String: String], parsedRoute: AppNotificationRoute?, messageId: String?, source: NotificationRouteSource) {}
    func shouldSuppressForegroundBanner(for userInfo: [AnyHashable: Any]) -> Bool { false }
    func shouldSuppressForegroundBanner(for rawPayload: [String: String]) -> Bool { false }
    func handleOrderStatusChanged(orderCode: String, previousStatus: String?, currentStatus: String, storeName: String?) -> AppNotificationSaveResult { .skipped(reason: "noop") }
    func handleChatMessageReceived(roomId: String, storeId: String?, title: String?, messageId: String?, senderId: String?, preview: String) -> AppNotificationSaveResult { .skipped(reason: "noop") }
    func handleCommunityComment(postId: String, commentId: String?, actorUserId: String?, actorName: String?, preview: String?) -> AppNotificationSaveResult { .skipped(reason: "noop") }
    func handleCommunityLike(postId: String, commentId: String?, actorUserId: String?, actorName: String?) -> AppNotificationSaveResult { .skipped(reason: "noop") }
    func handleCommunityMention(postId: String, commentId: String?, actorUserId: String?, actorName: String?, preview: String?) -> AppNotificationSaveResult { .skipped(reason: "noop") }
    func markAsRead(id: String) {}
    func markAllAsRead() {}
    func deleteNotification(id: String) {}
    func deleteAll() {}
    func fetchNotifications() -> [AppNotification] { [] }
    func unreadCount() -> Int { 0 }
}

private struct RemoteNotificationPayload {
    static let typeKeys = ["type", "notificationType", "notification_type", "eventType", "event_type", "event", "category"]
    static let titleKeys = ["title"]
    static let bodyKeys = ["body", "message", "preview", "content"]
    static let orderCodeKeys = ["orderCode", "order_code", "orderId", "order_id"]
    static let orderStatusKeys = ["status", "order_status", "orderStatus"]
    static let storeNameKeys = ["store_name", "storeName"]
    static let chatRoomKeys = ["chatRoomId", "chat_room_id", "roomId", "room_id"]
    static let storeIdKeys = ["storeId", "store_id"]
    static let chatBusinessMessageIdKeys = ["chatId", "chat_id", "messageId", "message_id"]
    static let messageIdKeys = ["chatId", "chat_id", "messageId", "message_id", "notification_id", "notificationId", "gcm.message_id", "google.message_id", "aps.thread-id", "google.c.a.c_id"]
    static let senderIdKeys = ["senderId", "sender_id"]
    static let postKeys = ["postId", "post_id", "communityPostId", "community_post_id"]
    static let commentKeys = ["commentId", "comment_id", "replyId", "reply_id"]
    static let actorUserKeys = ["actorUserId", "actor_user_id", "actorId", "actor_id"]
    static let actorNameKeys = ["actor_name", "actorName"]
    static let communityEventKeys = ["eventType", "event_type", "communityEventType", "community_event_type"]
    static let previewKeys = ["preview", "content", "comment_preview", "commentPreview", "body", "message"]

    let rawPayload: [String: String]

    init(rawPayload: [String: String]) {
        self.rawPayload = rawPayload
    }

    init(userInfo: [AnyHashable: Any]) {
        rawPayload = NotificationRouteParser.flattenedPayload(from: userInfo)
    }

    var title: String? { string(for: Self.titleKeys) }
    var body: String? { string(for: Self.bodyKeys) }
    var type: String? { string(for: Self.typeKeys) }
    var source: String? { string(for: ["source", "debug_source"]) }
    var messageID: String { string(for: Self.messageIdKeys) ?? "unknown" }
    var typeValue: String { string(for: Self.typeKeys)?.lowercased() ?? "" }
    var communityEventValue: String { string(for: Self.communityEventKeys)?.lowercased() ?? "" }

    var isOrderStatus: Bool {
        containsAny(["order", "order_status", "payment", "review"], in: typeValue)
    }

    var isChatMessage: Bool {
        containsAny(["chat", "chat_message", "message"], in: typeValue)
    }

    var isCommunityEvent: Bool {
        isCommunityComment || isCommunityLike || isCommunityMention
    }

    var isCommunityComment: Bool {
        containsAny(["community_comment", "comment"], in: typeValue) || communityEventValue == "comment"
    }

    var isCommunityLike: Bool {
        containsAny(["community_like", "like"], in: typeValue) || communityEventValue == "like"
    }

    var isCommunityMention: Bool {
        containsAny(["community_mention", "mention"], in: typeValue) || communityEventValue == "mention"
    }

    func string(for keys: [String]) -> String? {
        for key in keys {
            if let value = rawPayload[key]?.trimmed.nilIfEmpty {
                return value
            }
        }
        return nil
    }

    func orderNotification(orderCode: String) -> AppNotification {
        let status = string(for: Self.orderStatusKeys) ?? "UNKNOWN"
        let messageId = string(for: Self.messageIdKeys)
        let id = messageId ?? DefaultAppNotificationService.stableID(parts: ["order", orderCode, status])
        let notificationType: AppNotificationType
        if containsAny(["payment", "paid"], in: typeValue) {
            notificationType = .payment
        } else if containsAny(["review"], in: typeValue) {
            notificationType = .review
        } else {
            notificationType = .orderStatus
        }
        return AppNotification(
            id: id,
            type: notificationType,
            title: title ?? "주문 상태가 변경되었어요",
            body: body ?? "\(string(for: Self.storeNameKeys) ?? "주문") 상태가 변경되었어요.",
            createdAt: Date(),
            readState: .unread,
            route: .orderDetail(orderCode: orderCode),
            metadata: AppNotificationMetadata(orderCode: orderCode, orderStatus: status, rawPayload: rawPayload)
        )
    }

    func chatNotification(roomId: String) -> AppNotification {
        let messageId = string(for: Self.chatBusinessMessageIdKeys)
        let storeId = string(for: Self.storeIdKeys)
        let displayTitle = title ?? "새 채팅 메시지"
        let identity = DefaultAppNotificationService.chatNotificationIdentity(
            rawPayload: rawPayload,
            route: .chatRoom(roomId: roomId, storeId: storeId, title: displayTitle),
            messageId: messageId,
            senderId: string(for: Self.senderIdKeys),
            preview: body
        )
        let id = identity.rawValue
        return AppNotification(
            id: id,
            type: .chatMessage,
            title: "새 채팅 메시지",
            body: body ?? "\(displayTitle)에서 새 메시지가 도착했어요.",
            createdAt: Date(),
            readState: .unread,
            route: .chatRoom(roomId: roomId, storeId: storeId, title: displayTitle),
            metadata: AppNotificationMetadata(roomId: roomId, storeId: storeId, messageId: messageId, senderId: string(for: Self.senderIdKeys), rawPayload: rawPayload)
        )
    }

    func communityNotification(postId: String, type: AppNotificationType, eventType: String) -> AppNotification {
        let commentId = string(for: Self.commentKeys)
        let actorUserId = string(for: Self.actorUserKeys)
        let id = string(for: Self.messageIdKeys)
            ?? DefaultAppNotificationService.stableID(parts: ["community", postId, commentId ?? "-", actorUserId ?? "-", eventType])
        return AppNotification(
            id: id,
            type: type,
            title: title ?? defaultCommunityTitle(type: type),
            body: string(for: Self.previewKeys) ?? defaultCommunityBody(type: type),
            createdAt: Date(),
            readState: .unread,
            route: .communityPost(postId: postId, commentId: commentId),
            metadata: AppNotificationMetadata(postId: postId, commentId: commentId, actorUserId: actorUserId, communityEventType: eventType, rawPayload: rawPayload)
        )
    }

    func systemNotification() -> AppNotification {
        let id = string(for: Self.messageIdKeys)
            ?? DefaultAppNotificationService.stableID(parts: ["system", title ?? "-", body ?? "-", DefaultAppNotificationService.timeBucket()])
        return AppNotification(
            id: id,
            type: .system,
            title: title ?? "알림",
            body: body ?? "새 알림이 도착했어요.",
            createdAt: Date(),
            readState: .unread,
            route: .none,
            metadata: AppNotificationMetadata(rawPayload: rawPayload)
        )
    }

    private func defaultCommunityTitle(type: AppNotificationType) -> String {
        switch type {
        case .communityComment:
            return "새 댓글이 달렸어요"
        case .communityLike:
            return "좋아요가 눌렸어요"
        case .communityMention:
            return "댓글에서 나를 언급했어요"
        default:
            return "커뮤니티 알림"
        }
    }

    private func defaultCommunityBody(type: AppNotificationType) -> String {
        switch type {
        case .communityComment:
            return "내 게시글에 새로운 댓글이 달렸어요."
        case .communityLike:
            return "내 게시글 또는 댓글에 새로운 반응이 있어요."
        case .communityMention:
            return "댓글에서 나를 언급했어요."
        default:
            return "커뮤니티에 새로운 반응이 있어요."
        }
    }

    private func containsAny(_ needles: [String], in value: String) -> Bool {
        needles.contains { value.contains($0) }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedNotificationBody: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    var nilIfUnknown: String? {
        let normalized = trimmed
        guard !normalized.isEmpty, normalized != "unknown" else {
            return nil
        }
        return normalized
    }
}
