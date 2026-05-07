import Foundation

@MainActor
protocol AppNotificationRouting: AnyObject {
    func route(to route: AppNotificationRoute)
    func handleNotificationTap(route: AppNotificationRoute, messageId: String?, source: NotificationRouteSource)
}

protocol ChatRouteHydrating: Sendable {
    func hydrate(route: AppNotificationRoute, source: NotificationRouteSource) async -> ChatRouteHydrationResult
}

enum ChatRouteHydrationResult: Sendable, Equatable {
    case success(AppNotificationRoute)
    case rejected(reason: String)
}

struct DefaultChatRouteHydrator: ChatRouteHydrating {
    private let chatRepository: ChatRepository
    private let storeContextCache: any ChatRoomStoreContextCaching

    init(
        chatRepository: ChatRepository,
        storeContextCache: any ChatRoomStoreContextCaching = UserDefaultsChatRoomStoreContextCache.shared
    ) {
        self.chatRepository = chatRepository
        self.storeContextCache = storeContextCache
    }

    func hydrate(route: AppNotificationRoute, source: NotificationRouteSource) async -> ChatRouteHydrationResult {
        guard case .chatRoom(let roomId, let storeId, let title) = route else {
            return .success(route)
        }

        let normalizedRoomId = roomId.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger(category: "PushRouteID").debug("[PushRouteID] payloadRoomId=\(roomId) normalizedRoomId=\(normalizedRoomId) source=\(source.rawValue)")
        guard !normalizedRoomId.isEmpty else {
            Logger(category: "ChatRouteHydration").warning("[ChatRouteHydration] failed roomId=- reason=invalidRoomId")
            return .rejected(reason: "invalidRoomId")
        }

        Logger(category: "ChatRouteHydration").debug("[ChatRouteHydration] start roomId=\(normalizedRoomId)")
        if let cachedContext = storeContextCache.context(for: normalizedRoomId) {
            Logger(category: "ChatRouteHydration").debug("[ChatRouteHydration] localLookup roomId=\(normalizedRoomId) hit=true")
            Logger(category: "ChatRouteHydration").debug("[ChatRouteHydration] success roomId=\(normalizedRoomId) storeIdExists=true opponentIdExists=\(!cachedContext.opponentID.isEmpty) titleExists=\(!cachedContext.storeName.isEmpty)")
            return .success(.chatRoom(
                roomId: normalizedRoomId,
                storeId: cachedContext.storeID,
                title: cachedContext.storeName
            ))
        }

        Logger(category: "ChatRouteHydration").debug("[ChatRouteHydration] localLookup roomId=\(normalizedRoomId) hit=false")
        Logger(category: "ChatRouteHydration").debug("[ChatRouteHydration] remoteFetch start roomId=\(normalizedRoomId)")
        do {
            let rooms = try await chatRepository.fetchChatRooms()
            guard let room = rooms.first(where: { $0.id == normalizedRoomId }) else {
                Logger(category: "ChatRouteHydration").warning("[ChatRouteHydration] failed roomId=\(normalizedRoomId) reason=notFound")
                return .rejected(reason: "notFound")
            }

            let hydratedTitle = room.storeName?.nilIfEmpty
                ?? room.opponentName?.nilIfEmpty
                ?? title?.nilIfEmpty
                ?? "채팅"
            let hydratedStoreId = room.storeID?.nilIfEmpty ?? storeId?.nilIfEmpty
            let opponentIdExists = room.opponentID?.nilIfEmpty != nil
                || rooms.first(where: { $0.id == normalizedRoomId })?.participants.isEmpty == false
            Logger(category: "ChatRouteHydration").debug("[ChatRouteHydration] success roomId=\(normalizedRoomId) storeIdExists=\(hydratedStoreId != nil) opponentIdExists=\(opponentIdExists) titleExists=\(!hydratedTitle.isEmpty)")
            return .success(.chatRoom(roomId: normalizedRoomId, storeId: hydratedStoreId, title: hydratedTitle))
        } catch {
            Logger(category: "ChatRouteHydration").warning("[ChatRouteHydration] failed roomId=\(normalizedRoomId) reason=network")
            return .rejected(reason: "network")
        }
    }
}

@MainActor
final class AppNotificationRouter: AppNotificationRouting {
    private weak var appState: AppState?
    private let pendingRouteStore: PendingNotificationRouteStore
    private var navigationReady = false
    private let dedupeStore: PushNotificationDedupeStore
    private var chatRouteHydrator: (any ChatRouteHydrating)?

    init(
        pendingRouteStore: PendingNotificationRouteStore,
        dedupeInterval: TimeInterval = 10,
        now: @escaping () -> Date = Date.init
    ) {
        self.pendingRouteStore = pendingRouteStore
        self.dedupeStore = PushNotificationDedupeStore(ttl: dedupeInterval, now: now)
    }

    func attach(appState: AppState) {
        self.appState = appState
    }

    func setChatRouteHydrator(_ hydrator: any ChatRouteHydrating) {
        chatRouteHydrator = hydrator
    }

    func setNavigationReady(_ isReady: Bool) {
        navigationReady = isReady
        routePendingIfNeeded()
    }

    func route(to route: AppNotificationRoute) {
        handleRoute(route: route, messageId: nil, source: .notificationCenter)
    }

    func handleNotificationTap(route: AppNotificationRoute, messageId: String?, source: NotificationRouteSource) {
        handleRoute(route: route, messageId: messageId, source: source)
    }

    private func handleRoute(
        route: AppNotificationRoute,
        messageId: String?,
        source: NotificationRouteSource,
        skipsDedupe: Bool = false
    ) {
        let key = dedupeKey(route: route, messageId: messageId, source: source)
        Logger(category: "DeepLink").debug("[DeepLink] received source=\(source.rawValue) route=\(route.logRouteName) authState=\(authStateLogValue)")
        Logger(category: "PushDeepLink").debug("[PushDeepLink] handle thread=\(Thread.isMainThread ? "main" : "background") authReady=\(isAuthReady) navigationReady=\(navigationReady) route=\(route.logRouteName) \(route.logIdentifier)")

        if !skipsDedupe, !dedupeStore.accept(key: key, phase: .navigate) {
            return
        }

        guard let appState else {
            storePending(route: route, messageId: messageId, source: source, dedupeKey: key, reason: "routerUnavailable")
            return
        }

        guard appState.launchPhase == .ready else {
            storePending(route: route, messageId: messageId, source: source, dedupeKey: key, reason: "authNotReady")
            return
        }

        guard appState.sessionStore.isAuthenticated else {
            storePending(route: route, messageId: messageId, source: source, dedupeKey: key, reason: "authNotReady")
            return
        }

        guard navigationReady else {
            storePending(route: route, messageId: messageId, source: source, dedupeKey: key, reason: "navigationNotReady")
            return
        }

        guard appState.activeNotificationRoute != route,
              appState.pendingNotificationRoute != route else {
            Logger(category: "DeepLink").debug("[DeepLink] skipped reason=alreadyAtDestination route=\(route.debugDescription)")
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate skipped reason=alreadyAtDestination routeKey=\(route.routeKey)")
            return
        }

        if case .chatRoom = route, chatRouteHydrator != nil {
            Task { [weak self] in
                await self?.hydrateAndPublish(route: route, source: source)
            }
        } else {
            publish(route)
        }
    }

    private func hydrateAndPublish(route: AppNotificationRoute, source: NotificationRouteSource) async {
        let hydratedRoute: AppNotificationRoute
        if case .chatRoom = route, let chatRouteHydrator {
            switch await chatRouteHydrator.hydrate(route: route, source: source) {
            case .success(let route):
                hydratedRoute = route
            case .rejected(let reason):
                if case .chatRoom(let roomId, _, _) = route {
                    Logger(category: "DeepLink").error("[DeepLink] chat route rejected roomId=\(roomId) reason=\(reason)")
                    Logger(category: "NavigationQueue").error("[NavigationQueue] failed route=chat roomId=\(roomId) reason=\(reason)")
                }
                appState?.globalToast = GlobalToast(message: "채팅방 정보를 불러오지 못했습니다.")
                return
            }
        } else {
            hydratedRoute = route
        }

        publish(hydratedRoute)
    }

    private func publish(_ route: AppNotificationRoute) {
        guard let appState else { return }
        pendingRouteStore.clear()
        Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate start route=\(route.logRouteName)")
        Logger(category: "DeepLink").info("[DeepLink] navigate route=\(route.logRouteName) \(route.logIdentifier) thread=main selectedTab=\(appState.selectedTab.rawValue)")
        if route == .none {
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate fallback destination=notificationCenter reason=noCustomData")
        }
        appState.pendingNotificationRoute = route
    }

    func routePendingIfNeeded() {
        Logger(category: "PushDeepLink").debug("[PushDeepLink] readiness changed authReady=\(isAuthReady) navigationReady=\(navigationReady) pendingExists=\(pendingRouteStore.pendingRoute != nil)")
        guard let route = pendingRouteStore.pendingRoute,
              let appState,
              appState.launchPhase == .ready,
              appState.sessionStore.isAuthenticated,
              navigationReady else {
            return
        }
        let messageId = pendingRouteStore.pendingMessageId
        let source = pendingRouteStore.pendingSource ?? .remoteFCM
        pendingRouteStore.clear()
        Logger(category: "DeepLink").info("[DeepLink] resumeAfterAuth route=\(route.debugDescription)")
        Logger(category: "PushDeepLink").debug("[PushDeepLink] pending consumed route=\(route.logRouteName) \(route.logIdentifier)")
        handleRoute(route: route, messageId: messageId, source: source, skipsDedupe: true)
    }

    private var authStateLogValue: String {
        guard let appState else { return "navigationNotReady" }
        if appState.launchPhase != .ready {
            return "restoring"
        }
        return appState.sessionStore.isAuthenticated ? "authenticated" : "unauthenticated"
    }

    private var isAuthReady: Bool {
        guard let appState else { return false }
        return appState.launchPhase == .ready && appState.sessionStore.isAuthenticated
    }

    private func storePending(
        route: AppNotificationRoute,
        messageId: String?,
        source: NotificationRouteSource,
        dedupeKey: String,
        reason: String
    ) {
        pendingRouteStore.store(route: route, messageId: messageId, source: source, dedupeKey: dedupeKey)
        Logger(category: "DeepLink").warning("[DeepLink] navigate deferred reason=\(reason) route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "PushDeepLink").debug("[PushDeepLink] pending stored reason=\(reason) route=\(route.logRouteName) \(route.logIdentifier)")
    }

    private func dedupeKey(route: AppNotificationRoute, messageId: String?, source: NotificationRouteSource) -> String {
        if let messageId = messageId?.trimmingCharacters(in: .whitespacesAndNewlines), !messageId.isEmpty, messageId != "unknown" {
            return "navigate:\(source.rawValue):\(messageId):\(route.routeKey)"
        }
        return "navigate:\(source.rawValue):\(route.routeKey)"
    }
}

private extension AppNotificationRoute {
    var logRouteName: String {
        switch self {
        case .orderDetail:
            return "orderDetail"
        case .orderList:
            return "orderList"
        case .chatRoom:
            return "chat"
        case .communityPost:
            return "communityPost"
        case .communityList:
            return "communityList"
        case .paymentReceipt:
            return "paymentReceipt"
        case .none:
            return "none"
        }
    }

    var routeKey: String {
        switch self {
        case .orderDetail(let orderCode):
            return "order:\(orderCode)"
        case .orderList:
            return "orders"
        case .chatRoom(let roomId, _, _):
            return "chat:\(roomId)"
        case .communityPost(let postId, let commentId):
            return "post:\(postId):comment:\(commentId ?? "-")"
        case .communityList:
            return "community"
        case .paymentReceipt(let orderCode):
            return "payment:\(orderCode)"
        case .none:
            return "notice"
        }
    }

    var logIdentifier: String {
        switch self {
        case .orderDetail(let orderCode), .paymentReceipt(let orderCode):
            return "orderCode=\(orderCode)"
        case .chatRoom(let roomId, _, _):
            return "roomId=\(roomId)"
        case .communityPost(let postId, let commentId):
            return "postId=\(postId) commentIdExists=\(commentId != nil)"
        case .orderList, .communityList, .none:
            return ""
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
