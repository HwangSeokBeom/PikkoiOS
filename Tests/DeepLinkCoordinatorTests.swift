import XCTest
@testable import Pikko

@MainActor
final class DeepLinkCoordinatorTests: XCTestCase {
    func testAuthenticatedRouteExecutesImmediately() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)

        router.route(to: route)

        XCTAssertEqual(appState.pendingNotificationRoute, route)
    }

    func testAuthRestoringStoresPendingRoute() {
        let appState = makeAppState(authenticated: false, launchPhase: .restoringSession)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.communityPost(postId: "post-1", commentId: "comment-1")

        router.route(to: route)

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testPendingRouteExecutesAfterAuthCompletes() {
        let appState = makeAppState(authenticated: false, launchPhase: .restoringSession)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.orderDetail(orderCode: "order-1")
        router.route(to: route)

        appState.launchPhase = .ready
        appState.sessionStore.apply(session: makeSession())
        router.routePendingIfNeeded()

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertEqual(appState.pendingNotificationRoute, route)

        router.markNavigationCompleted(route: route)

        XCTAssertNil(store.pendingRoute)
    }

    func testUnauthenticatedRouteKeepsPendingForLoginGate() {
        let appState = makeAppState(authenticated: false, launchPhase: .ready)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)

        router.route(to: route)

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testSameRouteWithinShortWindowIsDeduped() {
        var currentDate = Date(timeIntervalSince1970: 100)
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = AppNotificationRouter(
            pendingRouteStore: PendingNotificationRouteStore(),
            dedupeInterval: 2,
            now: { currentDate }
        )
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        router.setNavigationReady(true)
        let firstRoute = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)
        let secondRoute = AppNotificationRoute.orderDetail(orderCode: "order-1")

        router.route(to: firstRoute)
        currentDate = Date(timeIntervalSince1970: 101)
        router.route(to: firstRoute)
        router.route(to: secondRoute)

        XCTAssertEqual(appState.pendingNotificationRoute, secondRoute)
    }

    func testAlreadyAtDestinationSkipsDuplicatePush() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.communityPost(postId: "post-1", commentId: nil)
        appState.activeNotificationRoute = route

        router.route(to: route)

        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testDifferentIdentifierAtSameDestinationTypeIsAllowed() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        appState.activeNotificationRoute = .communityPost(postId: "post-1", commentId: nil)
        let route = AppNotificationRoute.communityPost(postId: "post-2", commentId: nil)

        router.route(to: route)

        XCTAssertEqual(appState.pendingNotificationRoute, route)
    }

    func testUnknownNoticeRouteDoesNotEnterNavigationPipeline() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)

        router.route(to: .none)

        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testRouteNoneIsNeverStoredAsPendingNavigation() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(false)
        router.setNavigationReady(true)

        router.handleNotificationTap(route: .none, messageId: "message-1", source: .remoteFCM)

        XCTAssertNil(store.pendingRoute)
        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testNavigationNotReadyStoresPendingRouteUntilRootReady() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)

        router.handleNotificationTap(route: route, messageId: "message-1", source: .remoteFCM)

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertNil(appState.pendingNotificationRoute)

        router.setNavigationReady(true)

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertEqual(appState.pendingNotificationRoute, route)

        router.markNavigationCompleted(route: route)

        XCTAssertNil(store.pendingRoute)
    }

    func testInactiveSceneStoresValidPendingRouteAndReplaysAfterActive() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(false)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)

        router.handleNotificationTap(route: route, messageId: "message-1", source: .remoteFCM)

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertNil(appState.pendingNotificationRoute)

        router.setSceneActive(true)

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertEqual(appState.pendingNotificationRoute, route)

        router.markNavigationCompleted(route: route)

        XCTAssertNil(store.pendingRoute)
    }

    func testSameRemoteMessageTapIsDedupedByMessageIdAndRoute() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)

        router.handleNotificationTap(route: route, messageId: "message-1", source: .remoteFCM)
        appState.pendingNotificationRoute = nil
        router.handleNotificationTap(route: route, messageId: "message-1", source: .remoteFCM)

        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testSameRoomChatRoutePublishesOnlyOnePendingPresentation() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)
        let duplicateRoute = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: "store-1", title: "Updated")

        router.handleNotificationTap(route: route, messageId: "message-1", source: .remoteFCM)
        router.handleNotificationTap(route: duplicateRoute, messageId: "message-2", source: .remoteFCM)

        XCTAssertEqual(appState.pendingNotificationRoute, route)
    }

    func testDisplayedSameRoomPushSkipsPresentation() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-A", storeId: nil, title: nil)
        appState.activeNotificationRoute = route

        router.handleNotificationTap(
            route: .chatRoom(roomId: "room-A", storeId: "store-A", title: "Updated"),
            messageId: "message-1",
            source: .remoteFCM
        )

        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testActiveChatRoomTrackerSkipsSameRoomPresentation() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let tracker = ActiveChatRoomTracker()
        tracker.activeRoomId = "room-A"
        let router = AppNotificationRouter(
            pendingRouteStore: PendingNotificationRouteStore(),
            activeChatRoomTracker: tracker
        )
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        router.setNavigationReady(true)

        router.handleNotificationTap(
            route: .chatRoom(roomId: "room-A", storeId: "store-A", title: "Updated"),
            messageId: "message-1",
            source: .remoteFCM
        )

        XCTAssertNil(appState.pendingNotificationRoute)
    }

    func testDifferentRoomPushIsAllowedForRootReplacement() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        let currentRoute = AppNotificationRoute.chatRoom(roomId: "room-A", storeId: nil, title: nil)
        let incomingRoute = AppNotificationRoute.chatRoom(roomId: "room-B", storeId: nil, title: nil)
        appState.activeNotificationRoute = currentRoute

        router.handleNotificationTap(route: incomingRoute, messageId: "message-1", source: .remoteFCM)

        XCTAssertEqual(appState.pendingNotificationRoute, incomingRoute)
    }

    func testPendingChatRouteConsumesOnlyOnceAcrossReadinessEvents() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)
        store.store(
            route: route,
            messageId: "message-1",
            source: .remoteFCM,
            dedupeKey: "navigate:remoteFCM:message-1:chat:room-1"
        )

        router.setNavigationReady(true)
        XCTAssertEqual(appState.pendingNotificationRoute, route)
        XCTAssertEqual(store.pendingRoute, route)

        appState.pendingNotificationRoute = nil
        router.routePendingIfNeeded()

        XCTAssertEqual(store.pendingRoute, route)
        XCTAssertNil(appState.pendingNotificationRoute)

        router.markNavigationCompleted(route: route)

        XCTAssertNil(store.pendingRoute)
    }

    func testChatHydrationDoesNotBlockNavigationShell() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        router.setNavigationReady(true)
        router.setChatRouteHydrator(ChangingChatRouteHydrator())
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)

        router.handleNotificationTap(route: route, messageId: "message-1", source: .remoteFCM)

        XCTAssertEqual(appState.pendingNotificationRoute, route)
    }

    func testDuplicateForegroundChatPayloadSuppressesSecondVisibleBanner() {
        let service = makeNotificationService()
        let firstPayload = chatPayload(providerMessageId: "provider-1", chatId: "chat-1")
        let duplicatePayload = chatPayload(providerMessageId: "provider-2", chatId: "chat-1")

        XCTAssertFalse(service.shouldSuppressForegroundBanner(for: firstPayload))
        XCTAssertTrue(service.shouldSuppressForegroundBanner(for: duplicatePayload))
    }

    func testRemoteAndSocketChatNotificationShareStableIdentity() {
        let service = makeNotificationService()
        let payload = chatPayload(providerMessageId: "provider-1", chatId: "chat-1")

        service.handlePushNotificationEvent(PushNotificationEventFactory.makeEvent(
            rawPayload: payload,
            actionIdentifier: nil,
            lifecycle: .didReceiveRemoteNotification,
            source: .remoteFCM,
            isTap: false
        ))
        let socketResult = service.handleChatMessageReceived(
            roomId: "room-1",
            storeId: nil,
            title: "채팅",
            messageId: "chat-1",
            senderId: "sender-1",
            preview: "hello"
        )

        XCTAssertEqual(socketResult, .duplicate(id: "chatMessageId:chat-1"))
        XCTAssertEqual(service.fetchNotifications().count, 1)
    }

    func testDifferentProviderIdsWithSameFallbackChatIdentityDisplayOnce() {
        let service = makeNotificationService()
        let firstPayload = chatFallbackPayload(providerMessageId: "provider-1")
        let duplicatePayload = chatFallbackPayload(providerMessageId: "provider-2")

        XCTAssertFalse(service.shouldSuppressForegroundBanner(for: firstPayload))
        XCTAssertTrue(service.shouldSuppressForegroundBanner(for: duplicatePayload))
    }

    private func makeRouter(attachedTo appState: AppState) -> AppNotificationRouter {
        let router = AppNotificationRouter(pendingRouteStore: PendingNotificationRouteStore())
        router.attach(appState: appState)
        router.setSceneReady(true)
        router.setSceneActive(true)
        return router
    }

    private func makeAppState(authenticated: Bool, launchPhase: LaunchPhase) -> AppState {
        let suiteName = "DeepLinkCoordinatorTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let appState = AppState(
            sessionStore: SessionStore(
                tokenStore: StubDeepLinkTokenStore(),
                userDefaultsStore: UserDefaultsStore(userDefaults: userDefaults)
            ),
            cartStore: CartStore(cartRepository: InMemoryCartRepository())
        )
        appState.launchPhase = launchPhase
        if authenticated {
            appState.sessionStore.apply(session: makeSession())
        }
        return appState
    }

    private func makeSession() -> UserSession {
        UserSession(
            userID: "user-1",
            email: "user@example.com",
            displayName: "테스트",
            profileImagePath: nil,
            accessToken: "access-token",
            refreshToken: "refresh-token"
        )
    }

    private func makeNotificationService() -> DefaultAppNotificationService {
        let suiteName = "NotificationIdentityTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return DefaultAppNotificationService(
            repository: UserDefaultsAppNotificationRepository(store: UserDefaultsStore(userDefaults: userDefaults)),
            router: StubNotificationRouter(),
            activeChatRoomTracker: ActiveChatRoomTracker(),
            activeCommunityPostTracker: ActiveCommunityPostTracker(),
            diagnosticsStore: NotificationDiagnosticsStore()
        )
    }

    private func chatPayload(providerMessageId: String, chatId: String) -> [String: String] {
        [
            "type": "chat",
            "room_id": "room-1",
            "chatId": chatId,
            "gcm.message_id": providerMessageId,
            "senderId": "sender-1",
            "body": "hello",
            "createdAt": "2026-05-08T12:00:00Z"
        ]
    }

    private func chatFallbackPayload(providerMessageId: String) -> [String: String] {
        [
            "room_id": "room-1",
            "gcm.message_id": providerMessageId,
            "senderId": "sender-1",
            "body": "hello",
            "createdAt": "2026-05-08T12:00:00Z"
        ]
    }
}

private actor StubDeepLinkTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}

private struct ChangingChatRouteHydrator: ChatRouteHydrating {
    func hydrate(route: AppNotificationRoute, source: NotificationRouteSource) async -> ChatRouteHydrationResult {
        .success(.chatRoom(roomId: "room-1", storeId: "store-1", title: "Hydrated"))
    }
}

@MainActor
private final class StubNotificationRouter: AppNotificationRouting {
    func route(to route: AppNotificationRoute) {}
    func handleNotificationTap(route: AppNotificationRoute, messageId: String?, source: NotificationRouteSource) {}
    func markNavigationCompleted(route: AppNotificationRoute) {}
}
