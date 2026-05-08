import Foundation

@MainActor
protocol AppNotificationRouting: AnyObject {
    func route(to route: AppNotificationRoute)
    func handleNotificationTap(route: AppNotificationRoute, messageId: String?, source: NotificationRouteSource)
    func markNavigationCompleted(route: AppNotificationRoute)
}

struct NotificationRouteReadiness: Equatable, Sendable {
    var appSceneReady = false
    var appSceneActive = false
    var rootNavigationReady = false
    var authResolutionCompleted = false
    var sessionReady = false
    var tabRootReady = false
    var routerReady = false
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
    private let activeChatRoomTracker: ActiveChatRoomTracking?
    private var readiness = NotificationRouteReadiness()
    private var isConsumingPendingRoute = false
    private var consumedPendingKeys: Set<String> = []
    private let dedupeStore: PushNotificationDedupeStore
    private var chatRouteHydrator: (any ChatRouteHydrating)?

    init(
        pendingRouteStore: PendingNotificationRouteStore,
        activeChatRoomTracker: ActiveChatRoomTracking? = nil,
        dedupeInterval: TimeInterval = 10,
        now: @escaping () -> Date = Date.init
    ) {
        self.pendingRouteStore = pendingRouteStore
        self.activeChatRoomTracker = activeChatRoomTracker
        self.dedupeStore = PushNotificationDedupeStore(ttl: dedupeInterval, now: now)
    }

    func attach(appState: AppState) {
        MainActorStateAssertions.assertMainActorForUIState("AppNotificationRouter.attach")
        self.appState = appState
        readiness.routerReady = true
    }

    func setChatRouteHydrator(_ hydrator: any ChatRouteHydrating) {
        chatRouteHydrator = hydrator
    }

    func setNavigationReady(_ isReady: Bool) {
        MainActorStateAssertions.assertMainActorForUIState("AppNotificationRouter.setNavigationReady")
        readiness.rootNavigationReady = isReady
        readiness.tabRootReady = isReady
        refreshStateDerivedReadiness()
        logReadiness(targetTabReady: isReady)
        routePendingIfNeeded()
    }

    func setSceneReady(_ isReady: Bool) {
        MainActorStateAssertions.assertMainActorForUIState("AppNotificationRouter.setSceneReady")
        readiness.appSceneReady = isReady
        refreshStateDerivedReadiness()
        logReadiness(targetTabReady: readiness.tabRootReady)
        routePendingIfNeeded()
    }

    func setSceneActive(_ isActive: Bool) {
        MainActorStateAssertions.assertMainActorForUIState("AppNotificationRouter.setSceneActive")
        readiness.appSceneActive = isActive
        refreshStateDerivedReadiness()
        logReadiness(targetTabReady: readiness.tabRootReady)
        routePendingIfNeeded()
    }

    func route(to route: AppNotificationRoute) {
        handleRoute(route: route, messageId: nil, source: .notificationCenter)
    }

    func handleNotificationTap(route: AppNotificationRoute, messageId: String?, source: NotificationRouteSource) {
        handleRoute(route: route, messageId: messageId, source: source)
    }

    func markNavigationCompleted(route: AppNotificationRoute) {
        MainActorStateAssertions.assertMainActorForUIState("AppNotificationRouter.markNavigationCompleted")
        let pendingRoute = pendingRouteStore.pendingRoute
        let isMatchingChat = route.chatRoomId.map { pendingRoute?.chatRoomId == $0 } ?? false
        guard pendingRoute == route || isMatchingChat else { return }
        pendingRouteStore.clear()
        Logger(category: "PendingPushRoute").debug("[PendingPushRoute] clear route=\(route.logRouteName) \(route.logIdentifier) reason=navigated")
    }

    private func handleRoute(
        route: AppNotificationRoute,
        messageId: String?,
        source: NotificationRouteSource,
        skipsDedupe: Bool = false
    ) {
        MainActorStateAssertions.assertMainThreadForNavigation("AppNotificationRouter.handleRoute")
        Logger(category: "ThreadCheck").debug("[ThreadCheck] component=PushDeepLink operation=handle isMainThread=\(Thread.isMainThread)")
        guard route != .none else {
            Logger(category: "DeepLink").warning("[DeepLink] navigation skipped reason=invalidRoute route=none source=\(source.rawValue)")
            Logger(category: "PushDeepLink").warning("[PushDeepLink] navigation skipped reason=invalidRoute messageId=\(messageId ?? "unknown")")
            return
        }
        let key = dedupeKey(route: route, messageId: messageId, source: source)
        Logger(category: "DeepLink").debug("[DeepLink] received source=\(source.rawValue) route=\(route.logRouteName) authState=\(authStateLogValue)")
        refreshStateDerivedReadiness()
        Logger(category: "PushDeepLink").debug("[PushDeepLink] handle thread=\(Thread.isMainThread ? "main" : "background") authReady=\(isAuthReady) navigationReady=\(readiness.rootNavigationReady) route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "PushRouteQueue").debug("[PushRouteQueue] enqueue routeKey=\(route.routeKey) source=\(source.rawValue) pendingCount=\(pendingRouteStore.pendingRoute == nil ? 0 : 1)")

        if !skipsDedupe, !dedupeStore.accept(key: key, source: source.rawValue, phase: .navigate) {
            return
        }

        guard let appState else {
            storePending(route: route, messageId: messageId, source: source, dedupeKey: key, reason: "routerUnavailable")
            return
        }

        if let reason = retainedReason(for: route) {
            storePending(route: route, messageId: messageId, source: source, dedupeKey: key, reason: reason)
            return
        }

        if case .chatRoom(let roomId, _, _) = route {
            Logger(category: "ChatNavigation").debug("[ChatNavigation] open requested roomId=\(roomId) source=\(source.rawValue)")
        }

        guard !isAlreadyActiveOrPending(route: route, appState: appState) else {
            Logger(category: "DeepLink").debug("[DeepLink] skipped reason=alreadyAtDestination route=\(route.debugDescription)")
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate skipped reason=alreadyAtDestination routeKey=\(route.routeKey)")
            let isMatchingPendingChat = route.chatRoomId.map { pendingRouteStore.pendingRoute?.chatRoomId == $0 } ?? false
            if pendingRouteStore.pendingRoute == route || isMatchingPendingChat {
                pendingRouteStore.clear()
                Logger(category: "PendingPushRoute").debug("[PendingPushRoute] clear route=\(route.logRouteName) reason=alreadyAtDestination messageId=\(messageId ?? "unknown")")
            }
            if case .chatRoom(let roomId, _, _) = route {
                Logger(category: "ChatNavigation").debug("[ChatNavigation] requested roomId=\(roomId) source=\(source.rawValue) currentRoomId=\(roomId) stackContains=true")
                Logger(category: "ChatNavigation").debug("[ChatNavigation] open skipped reason=alreadyTop roomId=\(roomId)")
            }
            return
        }

        publish(route, source: source)
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
                Logger(category: "PushRouteConsume").error("[PushRouteConsume] failed routeKey=\(route.routeKey) error=\(reason)")
                appState?.globalToast = GlobalToast(message: "채팅방 정보를 불러오지 못했습니다.")
                return
            }
        } else {
            hydratedRoute = route
        }

        publish(hydratedRoute, source: source)
    }

    private func publish(_ route: AppNotificationRoute, source: NotificationRouteSource) {
        MainActorStateAssertions.assertMainThreadForNavigation("AppNotificationRouter.publish")
        guard let appState else { return }
        Logger(category: "ThreadCheck").debug("[ThreadCheck] component=NavigationQueue operation=publish isMainThread=\(Thread.isMainThread)")
        Logger(category: "PushRouteConsume").debug("[PushRouteConsume] routeKey=\(route.routeKey) result=started")
        Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate start route=\(route.logRouteName)")
        Logger(category: "DeepLink").info("[DeepLink] navigate route=\(route.logRouteName) \(route.logIdentifier) thread=main selectedTab=\(appState.selectedTab.rawValue)")
        appState.pendingNotificationRoute = route
        appState.pendingNotificationRouteSource = source
        Logger(category: "PushRouteConsume").info("[PushRouteConsume] routeKey=\(route.routeKey) result=completed destination=\(route.logRouteName)")
    }

    func routePendingIfNeeded() {
        MainActorStateAssertions.assertMainThreadForNavigation("AppNotificationRouter.routePendingIfNeeded")
        refreshStateDerivedReadiness()
        logReadiness(targetTabReady: navigationReady)
        Logger(category: "PushDeepLink").debug("[PushDeepLink] readiness changed authReady=\(isAuthReady) navigationReady=\(navigationReady) pendingExists=\(pendingRouteStore.pendingRoute != nil)")
        guard !isConsumingPendingRoute else {
            Logger(category: "PendingPushRoute").debug("[PendingPushRoute] consumeCheck ready=false reason=alreadyProcessing")
            return
        }
        guard let route = pendingRouteStore.pendingRoute else { return }
        guard route != .none else {
            pendingRouteStore.clear()
            Logger(category: "PendingPushRoute").warning("[PendingPushRoute] consume skipped reason=invalidRoute route=none")
            return
        }
        let retainedReason = pendingRetainedReason(for: route)
        Logger(category: "PendingPushRoute").debug("[PendingPushRoute] consumeCheck ready=\(retainedReason == nil) reason=\(retainedReason ?? "ready")")
        guard retainedReason == nil else {
            Logger(category: "PendingPushRoute").debug("[PendingPushRoute] retained reason=\(retainedReason ?? "unknown")")
            return
        }
        guard appState != nil else { return }
        isConsumingPendingRoute = true
        defer { isConsumingPendingRoute = false }
        let messageId = pendingRouteStore.pendingMessageId
        let source = pendingRouteStore.pendingSource ?? .remoteFCM
        let pendingKey = pendingRouteStore.pendingDedupeKey ?? dedupeKey(route: route, messageId: messageId, source: source)
        guard !consumedPendingKeys.contains(pendingKey) else {
            Logger(category: "PendingPushRoute").debug("[PendingPushRoute] consume pendingKey=\(pendingKey) consumedOnce=true cleared=false reason=alreadyPublished")
            return
        }
        consumedPendingKeys.insert(pendingKey)
        Logger(category: "DeepLink").info("[DeepLink] resumeAfterAuth route=\(route.debugDescription)")
        Logger(category: "PushDeepLink").debug("[PushDeepLink] pending consumed route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "PendingPushRoute").debug("[PendingPushRoute] replay route=\(route.logRouteName) sceneActive=true messageId=\(messageId ?? "unknown")")
        if case .chatRoom(let roomId, _, _) = route {
            Logger(category: "PendingPushRoute").debug("[PendingPushRoute] replay route=chat roomId=\(roomId) sceneActive=\(readiness.appSceneActive) authReady=\(isAuthReady) navigationReady=\(navigationReady) targetTabReady=\(readiness.tabRootReady)")
        }
        Logger(category: "PendingPushRoute").debug("[PendingPushRoute] consumed messageId=\(messageId ?? "unknown") route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "PushLifecycle").debug("[PushLifecycle] pendingConsumed target=\(route.logRouteName) \(route.logIdentifier)")
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

    private var navigationReady: Bool {
        readiness.rootNavigationReady && readiness.tabRootReady
    }

    private func storePending(
        route: AppNotificationRoute,
        messageId: String?,
        source: NotificationRouteSource,
        dedupeKey: String,
        reason: String
    ) {
        MainActorStateAssertions.assertMainActorForUIState("AppNotificationRouter.storePending")
        Logger(category: "ThreadCheck").debug("[ThreadCheck] component=PendingPushRoute operation=store isMainThread=\(Thread.isMainThread)")
        guard route != .none else {
            Logger(category: "PendingPushRoute").warning("[PendingPushRoute] store skipped reason=invalidRoute route=none messageId=\(messageId ?? "unknown")")
            return
        }
        pendingRouteStore.store(route: route, messageId: messageId, source: source, dedupeKey: dedupeKey)
        logGate(route: route)
        Logger(category: "DeepLink").warning("[DeepLink] navigate deferred reason=\(reason) route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "PushDeepLink").debug("[PushDeepLink] pending stored reason=\(reason) route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "PushLifecycle").debug("[PushLifecycle] pendingStored reason=\(reason) target=\(route.logRouteName) \(route.logIdentifier)")
        if case .chatRoom(let roomId, _, _) = route {
            Logger(category: "PendingPushRoute").debug("[PendingPushRoute] store route=chat roomId=\(roomId) reason=\(reason)")
        } else {
            Logger(category: "PendingPushRoute").debug("[PendingPushRoute] store route=\(route.logRouteName) reason=\(reason) messageId=\(messageId ?? "unknown")")
        }
        if reason == "authNotReady" || reason == "sessionNotReady" {
            Logger(category: "PushRouteGate").warning("[PushRouteGate] route requires auth but session failed, preserving route until login")
        }
    }

    private func pendingRetainedReason(for route: AppNotificationRoute) -> String? {
        retainedReason(for: route)
    }

    private func retainedReason(for route: AppNotificationRoute) -> String? {
        refreshStateDerivedReadiness()
        logGate(route: route)
        guard let appState else { return "rootNotReady" }
        guard readiness.routerReady else { return "routerNotReady" }
        guard readiness.appSceneReady else { return "appSceneNotReady" }
        guard readiness.appSceneActive else { return "appSceneNotActive" }
        guard appState.launchPhase == .ready else { return "rootNotReady" }
        if route.requiresAuthentication {
            guard appState.sessionStore.isAuthenticated else { return "sessionNotReady" }
        }
        guard readiness.rootNavigationReady else { return "navigationNotReady" }
        guard readiness.tabRootReady else { return "tabRootNotReady" }
        return nil
    }

    private func logReadiness(targetTabReady: Bool) {
        let firebaseConfigured = true
        Logger(category: "AppReadiness").debug("[AppReadiness] firebaseConfigured=\(firebaseConfigured) authResolved=\(readiness.authResolutionCompleted) authReady=\(isAuthReady) rootMounted=\(readiness.rootNavigationReady) tabRootsInitialized=\(readiness.tabRootReady) navigationReady=\(navigationReady) targetTabReady=\(targetTabReady)")
    }

    private func logGate(route: AppNotificationRoute) {
        Logger(category: "PushRouteGate").debug("[PushRouteGate] appReady=\(readiness.appSceneReady) sceneActive=\(readiness.appSceneActive) sessionReady=\(readiness.sessionReady) navigationReady=\(navigationReady) authState=\(authStateLogValue)")
    }

    private func refreshStateDerivedReadiness() {
        readiness.routerReady = appState != nil
        readiness.authResolutionCompleted = appState?.launchPhase == .ready
        readiness.sessionReady = appState?.sessionStore.isAuthenticated == true
    }

    private func dedupeKey(route: AppNotificationRoute, messageId: String?, source: NotificationRouteSource) -> String {
        if let messageId = messageId?.trimmingCharacters(in: .whitespacesAndNewlines), !messageId.isEmpty, messageId != "unknown" {
            return "navigate:\(source.rawValue):\(messageId):\(route.routeKey)"
        }
        return "navigate:\(source.rawValue):\(route.routeKey)"
    }

    private func isAlreadyActiveOrPending(route: AppNotificationRoute, appState: AppState) -> Bool {
        if let roomId = route.chatRoomId {
            return appState.activeNotificationRoute?.chatRoomId == roomId
                || appState.pendingNotificationRoute?.chatRoomId == roomId
                || activeChatRoomTracker?.activeRoomId == roomId
        }

        return appState.activeNotificationRoute == route
            || appState.pendingNotificationRoute == route
    }
}

extension AppNotificationRouter {
    struct ChatPresentationReducer {
        enum Action: String, Equatable {
            case present
            case replace
            case skip
            case clearDuplicate
        }

        struct Decision: Equatable {
            let action: Action
            let removedQueuedDuplicateCount: Int
        }

        static func reduce(
            incomingRoute: AppNotificationRoute,
            currentSheetRoute: AppNotificationRoute?,
            currentPresentedChatRoomId: String?,
            pendingRoute: AppNotificationRoute?,
            navigationQueue: [AppNotificationRoute]
        ) -> Decision {
            guard let incomingRoomId = incomingRoute.chatRoomId else {
                return Decision(action: .present, removedQueuedDuplicateCount: 0)
            }

            let currentRoomId = currentPresentedChatRoomId ?? currentSheetRoute?.chatRoomId
            let queuedDuplicates = navigationQueue.filter { $0.chatRoomId == incomingRoomId }.count
            let pendingDuplicate = pendingRoute?.chatRoomId == incomingRoomId

            if currentRoomId == incomingRoomId {
                return Decision(
                    action: queuedDuplicates > 0 || pendingDuplicate ? .clearDuplicate : .skip,
                    removedQueuedDuplicateCount: queuedDuplicates
                )
            }

            if currentRoomId != nil {
                return Decision(action: .replace, removedQueuedDuplicateCount: queuedDuplicates)
            }

            return Decision(
                action: queuedDuplicates > 0 || pendingDuplicate ? .clearDuplicate : .present,
                removedQueuedDuplicateCount: queuedDuplicates
            )
        }
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
        case .storeDetail:
            return "storeDetail"
        case .videoDetail:
            return "videoDetail"
        case .shorts:
            return "shorts"
        case .communityPost:
            return "communityPost"
        case .communityList:
            return "communityList"
        case .cart:
            return "cart"
        case .profile:
            return "profile"
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
        case .storeDetail(let storeId):
            return "store:\(storeId)"
        case .videoDetail(let videoId):
            return "video:\(videoId)"
        case .shorts(let videoId):
            return "shorts:\(videoId ?? "-")"
        case .communityPost(let postId, let commentId):
            return "post:\(postId):comment:\(commentId ?? "-")"
        case .communityList:
            return "community"
        case .cart:
            return "cart"
        case .profile:
            return "profile"
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
        case .storeDetail(let storeId):
            return "storeId=\(storeId)"
        case .videoDetail(let videoId):
            return "videoId=\(videoId)"
        case .shorts(let videoId):
            return "videoIdExists=\(videoId?.isEmpty == false)"
        case .communityPost(let postId, let commentId):
            return "postId=\(postId) commentIdExists=\(commentId != nil)"
        case .orderList, .communityList, .cart, .profile, .none:
            return ""
        }
    }

    var requiresAuthentication: Bool {
        switch self {
        case .none:
            return false
        case .orderDetail, .orderList, .chatRoom, .storeDetail, .videoDetail, .shorts, .communityPost, .communityList, .cart, .profile, .paymentReceipt:
            return true
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
