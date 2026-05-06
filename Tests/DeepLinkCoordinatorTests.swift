import XCTest
@testable import Pikko

@MainActor
final class DeepLinkCoordinatorTests: XCTestCase {
    func testAuthenticatedRouteExecutesImmediately() {
        let appState = makeAppState(authenticated: true, launchPhase: .ready)
        let router = makeRouter(attachedTo: appState)
        let route = AppNotificationRoute.chatRoom(roomId: "room-1", storeId: nil, title: nil)

        router.route(to: route)

        XCTAssertEqual(appState.pendingNotificationRoute, route)
    }

    func testAuthRestoringStoresPendingRoute() {
        let appState = makeAppState(authenticated: false, launchPhase: .restoringSession)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
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
        let route = AppNotificationRoute.orderDetail(orderCode: "order-1")
        router.route(to: route)

        appState.launchPhase = .ready
        appState.sessionStore.apply(session: makeSession())
        router.routePendingIfNeeded()

        XCTAssertNil(store.pendingRoute)
        XCTAssertEqual(appState.pendingNotificationRoute, route)
    }

    func testUnauthenticatedRouteKeepsPendingForLoginGate() {
        let appState = makeAppState(authenticated: false, launchPhase: .ready)
        let store = PendingNotificationRouteStore()
        let router = AppNotificationRouter(pendingRouteStore: store)
        router.attach(appState: appState)
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
        let route = AppNotificationRoute.communityPost(postId: "post-1", commentId: nil)
        appState.activeNotificationRoute = route

        router.route(to: route)

        XCTAssertNil(appState.pendingNotificationRoute)
    }

    private func makeRouter(attachedTo appState: AppState) -> AppNotificationRouter {
        let router = AppNotificationRouter(pendingRouteStore: PendingNotificationRouteStore())
        router.attach(appState: appState)
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
}

private actor StubDeepLinkTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}
