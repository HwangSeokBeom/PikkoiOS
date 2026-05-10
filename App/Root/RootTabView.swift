import SwiftUI
import UIKit

@MainActor
struct RootTabView: View {
    @ObservedObject private var appState: AppState
    let featureBuilderFactory: FeatureBuilderFactory

    @State private var homePath = NavigationPath()
    @State private var orderPath = NavigationPath()
    @State private var videoPath = NavigationPath()
    @State private var communityPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var homeResetTrigger = 0
    @State private var videoResetTrigger = 0
    @State private var didLogInitialTabReload = false
    @State private var presentedNotificationRoute: NotificationRoutePresentation?
    @State private var currentPushedChatScopeKey: String?
    @State private var notificationNavigationQueue: [NotificationNavigationRequest] = []
    @State private var isDrainingNotificationNavigationQueue = false
    @StateObject private var keyboardObserver = RootTabKeyboardObserver()

    init(
        appState: AppState,
        featureBuilderFactory: FeatureBuilderFactory
    ) {
        _appState = ObservedObject(wrappedValue: appState)
        self.featureBuilderFactory = featureBuilderFactory
    }

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            ZStack {
                RootTabContainerView(path: $homePath, tab: .home, isActive: appState.selectedTab == .home) {
                    featureBuilderFactory.makeHomeView(resetTrigger: homeResetTrigger)
                }

                RootTabContainerView(path: $orderPath, tab: .order, isActive: appState.selectedTab == .order) {
                    featureBuilderFactory.makeOrderView()
                }

                RootTabContainerView(path: $videoPath, tab: .video, isActive: appState.selectedTab == .video) {
                    featureBuilderFactory.makeVideoListView(
                        resetTrigger: videoResetTrigger,
                        isTabActive: appState.selectedTab == .video
                    )
                }

                RootTabContainerView(path: $communityPath, tab: .community, isActive: appState.selectedTab == .community) {
                    featureBuilderFactory.makeCommunityView()
                }

                RootTabContainerView(path: $profilePath, tab: .profile, isActive: appState.selectedTab == .profile) {
                    featureBuilderFactory.makeProfileView()
                        .navigationDestination(for: NotificationChatPathRoute.self) { route in
                            featureBuilderFactory.makeChatView(
                                target: route.chatTarget,
                                presentationKind: .profileStack
                            )
                            .onDisappear {
                                if currentPushedChatScopeKey == route.roomScopeKey {
                                    currentPushedChatScopeKey = nil
                                }
                                if appState.activeNotificationRoute?.chatRouteScopeKey == route.roomScopeKey {
                                    appState.activeNotificationRoute = nil
                                    appState.activeNotificationRouteSource = nil
                                }
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardObserver.isKeyboardVisible {
                GeometryReader { proxy in
                    RootTabBarView(
                        selectedTab: appState.selectedTab,
                        screenWidth: proxy.size.width,
                        safeAreaBottom: proxy.safeAreaInsets.bottom,
                        onSelect: { tab in
                            handleTabSelection(tab)
                        }
                    )
                }
                .frame(height: RootTabBarMetrics.maximumTotalHeight)
                .zIndex(RootTabBarMetrics.zIndex)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            .easeOut(duration: keyboardObserver.animationDuration),
            value: keyboardObserver.isKeyboardVisible
        )
        .sheet(item: $presentedNotificationRoute, onDismiss: {
            handleNotificationPresentationDismissed()
        }) { presentation in
            NavigationStack {
                destinationView(for: presentation.route, source: presentation.source)
            }
        }
        .overlay(alignment: .top) {
            if let toast = appState.globalToast {
                ToastView(message: toast.message, tone: .warning)
                    .padding(.top, PikkoSpacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .onAppear {
            Logger(category: "NavigationQueue").debug("[NavigationQueue] rootMounted=true tabRootsInitialized=true selectedTab=\(appState.selectedTab.rawValue)")
            logInitialTabReloadIfNeeded()
            featureBuilderFactory.setNotificationNavigationReady(true)
            featureBuilderFactory.routePendingNotificationIfNeeded()
            scheduleNotificationRoute(appState.pendingNotificationRoute, source: appState.pendingNotificationRouteSource)
        }
        .onDisappear {
            featureBuilderFactory.setNotificationNavigationReady(false)
        }
        .onChange(of: appState.pendingNotificationRoute) { _, route in
            scheduleNotificationRoute(route, source: appState.pendingNotificationRouteSource)
        }
    }

    private func handleTabSelection(_ tab: RootTab) {
        MainActorStateAssertions.assertMainThreadForNavigation("RootTabView.handleTabSelection")
        let previousTab = appState.selectedTab
        logTabSwitch(from: previousTab, to: tab)

        guard tab != previousTab else {
            handleCurrentTabReselection(tab)
            return
        }

        appState.selectedTab = tab
        logTabReload(tab: tab, reason: "tabSwitchSkipped")
    }

    private func handleCurrentTabReselection(_ tab: RootTab) {
        MainActorStateAssertions.assertMainThreadForNavigation("RootTabView.handleCurrentTabReselection")
        if tab == .home {
            homePath = NavigationPath()
            homeResetTrigger += 1
            logTabReload(tab: tab, reason: "refresh")
            return
        }

        if tab == .video {
            videoPath = NavigationPath()
            videoResetTrigger += 1
            logTabReload(tab: tab, reason: "refresh")
            return
        }

        logTabReload(tab: tab, reason: "tabSwitchSkipped")
    }

    @ViewBuilder
    private func destinationView(for route: AppNotificationRoute, source: NotificationRouteSource?) -> some View {
        switch route {
        case .orderDetail(let orderCode), .paymentReceipt(let orderCode):
            featureBuilderFactory.makeOrderDetailView(orderID: orderCode)
        case .chatRoom:
            EmptyView()
        case .storeDetail(let storeId):
            featureBuilderFactory.makeStoreDetailView(storeID: storeId, source: "notification")
        case .videoDetail, .shorts:
            featureBuilderFactory.makeVideoListView()
        case .communityPost(let postId, let commentId):
            featureBuilderFactory.makeCommunityDetailView(postID: postId, initialCommentID: commentId)
        case .orderList:
            featureBuilderFactory.makeOrderView()
        case .communityList:
            featureBuilderFactory.makeCommunityView()
        case .cart:
            featureBuilderFactory.makeCartView()
        case .profile:
            featureBuilderFactory.makeProfileView()
        case .none:
            featureBuilderFactory.makeNotificationListView()
        }
    }

    private func scheduleNotificationRoute(_ route: AppNotificationRoute?, source: NotificationRouteSource?) {
        guard let route else { return }
        guard route != .none else {
            Logger(category: "NavigationQueue").warning("[NavigationQueue] enqueue skipped reason=invalidRoute route=none")
            return
        }
        Task { @MainActor in
            await Task.yield()
            enqueueNotificationRoute(route, source: source ?? .remoteFCM)
        }
    }

    private func enqueueNotificationRoute(_ route: AppNotificationRoute, source: NotificationRouteSource) {
        MainActorStateAssertions.assertMainThreadForNavigation("RootTabView.enqueueNotificationRoute")
        guard route != .none else {
            Logger(category: "NavigationQueue").warning("[NavigationQueue] enqueue skipped reason=invalidRoute route=none")
            return
        }
        let request = NotificationNavigationRequest(route: route, source: source)
        guard !notificationNavigationQueue.contains(request) else {
            Logger(category: "NavigationQueue").debug("[NavigationQueue] deferred reason=duplicatePending route=\(route.logRouteName) \(route.logIdentifier)")
            return
        }

        notificationNavigationQueue.append(request)
        Logger(category: "NavigationQueue").debug("[NavigationQueue] enqueue route=\(route.logRouteName) \(route.logIdentifier) source=\(source.rawValue)")
        drainNotificationNavigationQueueIfNeeded()
    }

    private func drainNotificationNavigationQueueIfNeeded() {
        MainActorStateAssertions.assertMainThreadForNavigation("RootTabView.drainNotificationNavigationQueueIfNeeded")
        guard !isDrainingNotificationNavigationQueue else { return }
        isDrainingNotificationNavigationQueue = true
        Task { @MainActor in
            var didDeferRoute = false
            defer {
                isDrainingNotificationNavigationQueue = false
                if !didDeferRoute, !notificationNavigationQueue.isEmpty {
                    drainNotificationNavigationQueueIfNeeded()
                }
            }

            Logger(category: "NavigationQueue").debug("[NavigationQueue] drain start pendingCount=\(notificationNavigationQueue.count)")
            while !notificationNavigationQueue.isEmpty {
                let request = notificationNavigationQueue.removeFirst()
                let didComplete = await performNotificationNavigation(request.route, source: request.source)
                if !didComplete {
                    didDeferRoute = true
                    break
                }
            }
        }
    }

    @discardableResult
    private func performNotificationNavigation(_ route: AppNotificationRoute, source: NotificationRouteSource) async -> Bool {
        MainActorStateAssertions.assertMainThreadForNavigation("RootTabView.performNotificationNavigation")
        guard route != .none else {
            Logger(category: "NavigationQueue").warning("[NavigationQueue] navigation skipped reason=invalidRoute route=none")
            appState.pendingNotificationRoute = nil
            appState.pendingNotificationRouteSource = nil
            return true
        }
        guard appState.launchPhase == .ready, appState.sessionStore.isAuthenticated else {
            notificationNavigationQueue.insert(NotificationNavigationRequest(route: route, source: source), at: 0)
            Logger(category: "NavigationQueue").debug("[NavigationQueue] deferred reason=authNotReady route=\(route.logRouteName) \(route.logIdentifier)")
            return false
        }

        let targetTab = targetTab(for: route)
        Logger(category: "ChatRouteOwner").debug("[ChatRouteOwner] policy=profileStack reason=\(route.isChatRoute ? "chatPushUsesTabNavigationPath" : "tabOwnedRoute")")
        Logger(category: "ChatRouteOwner").debug("[ChatRouteOwner] previousSelectedTab=\(appState.selectedTab.rawValue) targetTab=\(targetTab.rawValue)")
        Logger(category: "ChatRouteOwner").debug("[ChatRouteOwner] preserveReturnTab=false")

        if appState.selectedTab != targetTab {
            let previousTab = appState.selectedTab
            Logger(category: "ThreadCheck").debug("[ThreadCheck] component=RootTabView operation=selectedTabMutation isMainThread=\(Self.isCurrentMainThreadForLog())")
            Logger(category: "NavigationQueue").debug("[NavigationQueue] selectTab target=\(targetTab.rawValue) previous=\(previousTab.rawValue) route=\(route.logRouteName)")
            appState.selectedTab = targetTab
            await Task.yield()
        }

        guard appState.selectedTab == targetTab else {
            notificationNavigationQueue.insert(NotificationNavigationRequest(route: route, source: source), at: 0)
            Logger(category: "NavigationQueue").debug("[NavigationQueue] deferred reason=targetTabNotReady route=\(route.logRouteName) \(route.logIdentifier)")
            return false
        }

        Logger(category: "NavigationQueue").debug("[NavigationQueue] targetReady tab=\(targetTab.rawValue)")
        if route.isOrderRoute {
            Logger(category: "PushDeepLink").debug("[PushDeepLink] order lookup start source=GET /v1/orders")
            await featureBuilderFactory.refreshOrdersForSystemState(source: .pushTap, force: true)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] order lookup result matched=\(route.orderRouteIdentifier != nil)")
        }

        switch route {
        case .orderList:
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=orders")
        case .communityList:
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=community")
        case .storeDetail:
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=store")
        case .videoDetail, .shorts:
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=video")
        case .cart:
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=cart")
        case .profile:
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=profile")
        case .orderDetail:
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=orders orderCode=\(route.orderRouteIdentifier ?? "unknown")")
        case .paymentReceipt:
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=order")
        case .chatRoom:
            guard case .chatRoom(let roomId, let storeId, _) = route, !roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger(category: "DeepLink").error("[DeepLink] navigate failed reason=missingRoomId route=chat")
                Logger(category: "NavigationQueue").error("[NavigationQueue] failed route=chat roomId=- reason=missingRoomId")
                return true
            }
            let chatScopeKey = Self.chatRouteScopeKey(roomId: roomId, storeId: storeId)
            Logger(category: "PushRouteNavigate").debug("[PushRouteNavigate] start route=chat roomId=\(roomId)")
            Logger(category: "PushRouteNavigate").debug("[PushRouteNavigate] selectedTab=\(appState.selectedTab.rawValue)")
            Logger(category: "ChatRoute").debug("[ChatRoute] requested=\(chatScopeKey) action=push source=\(source.rawValue)")
            Logger(category: "ChatNavigation").debug("[ChatNavigation] open requested roomId=\(roomId) storeId=\(storeId ?? "-") source=\(source.rawValue)")
            let pathCountBefore = profilePath.count
            let queuedCountBefore = notificationNavigationQueue.count
            notificationNavigationQueue.removeAll { $0.route.chatRouteScopeKey == chatScopeKey }
            let removedDuplicateCount = queuedCountBefore - notificationNavigationQueue.count
            if removedDuplicateCount > 0 {
                Logger(category: "ChatRoute").debug("[ChatRoute] requested=\(chatScopeKey) action=skip reason=duplicateRoutePrevented")
                Logger(category: "ChatNavigation").warning("[ChatNavigation] duplicate prevented roomId=\(roomId) removedQueuedDuplicateCount=\(removedDuplicateCount)")
            }
            Logger(category: "NavigationPath").debug(
                "[NavigationPath] beforeCount=\(pathCountBefore) afterCount=\(profilePath.count) appendedRoute=none removedDuplicateCount=\(removedDuplicateCount)"
            )
            if currentPushedChatScopeKey == chatScopeKey {
                Logger(category: "ChatRoute").debug("[ChatRoute] requested=\(chatScopeKey) action=skip reason=alreadyTop")
                Logger(category: "ChatNavigation").debug("[ChatNavigation] open skipped reason=alreadyTop roomId=\(roomId)")
                appState.pendingNotificationRoute = nil
                appState.pendingNotificationRouteSource = nil
                Logger(category: "NavigationQueue").debug("[NavigationQueue] pendingRoute cleared reason=chatSkip roomId=\(roomId)")
                return true
            }
            if currentPushedChatScopeKey != nil {
                Logger(category: "ChatRoute").debug("[ChatRoute] requested=\(chatScopeKey) action=popToExisting reason=replaceExistingChatRoute")
                Logger(category: "ChatNavigation").debug("[ChatNavigation] replace reason=existingChatPathRoute roomId=\(roomId)")
                profilePath = NavigationPath()
                currentPushedChatScopeKey = nil
                await Task.yield()
            }
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            Logger(category: "ThreadCheck").debug("[ThreadCheck] component=RootTabView operation=NavigationPathAppend isMainThread=\(Self.isCurrentMainThreadForLog())")
            profilePath.append(NotificationChatPathRoute(route: route, source: source))
            currentPushedChatScopeKey = chatScopeKey
            Logger(category: "NavigationPath").debug(
                "[NavigationPath] beforeCount=\(pathCountBefore) afterCount=\(profilePath.count) appendedRoute=chat removedDuplicateCount=\(removedDuplicateCount)"
            )
            Logger(category: "ChatNavigation").debug("[ChatNavigation] stackAfter count=\(profilePath.count) chatRouteCount=1")
            Logger(category: "NavigationQueue").info("[NavigationQueue] set route=chat roomId=\(roomId) tab=profileStack")
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=chat")
            Logger(category: "PushRouteNavigate").debug("[PushRouteNavigate] completed route=chat roomId=\(roomId)")
        case .communityPost:
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=post")
        case .none:
            Logger(category: "PushDeepLink").warning("[PushDeepLink] navigation skipped reason=invalidRoute route=none")
            return true
        }

        appState.pendingNotificationRoute = nil
        appState.pendingNotificationRouteSource = nil
        featureBuilderFactory.markNotificationNavigationCompleted(route: route)
        if case .chatRoom = route {
            Logger(category: "PendingPushRoute").debug("[PendingPushRoute] clear route=chat \(route.logIdentifier) reason=navigated")
        }
        Logger(category: "NavigationQueue").debug("[NavigationQueue] pendingRoute cleared reason=complete route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "NavigationQueue").debug("[NavigationQueue] complete route=\(route.logRouteName) \(route.logIdentifier)")
        return true
    }

    private func handleNotificationPresentationDismissed() {
        let dismissedRoomId = presentedNotificationRoute?.route.chatRoomId
        let dismissedScopeKey = presentedNotificationRoute?.route.chatRouteScopeKey
        Logger(category: "ChatNavigation").debug("[ChatNavigation] pop requested reason=presentationDismissed top=\(dismissedRoomId ?? "nil")")
        appState.activeNotificationRoute = nil
        appState.activeNotificationRouteSource = nil
        presentedNotificationRoute = nil

        if let dismissedRoomId {
            let removedQueuedCount = notificationNavigationQueue.count
            notificationNavigationQueue.removeAll { $0.route.chatRouteScopeKey == dismissedScopeKey }
            let removedCount = removedQueuedCount - notificationNavigationQueue.count
            if appState.pendingNotificationRoute?.chatRouteScopeKey == dismissedScopeKey {
                appState.pendingNotificationRoute = nil
                appState.pendingNotificationRouteSource = nil
            }
            Logger(category: "ChatNavigation").debug(
                "[ChatNavigation] dismiss roomId=\(dismissedRoomId) clearedGlobalRoute=true clearedCurrentPresented=true removedQueuedCount=\(removedCount)"
            )
            if presentedNotificationRoute?.route.chatRouteScopeKey == dismissedScopeKey
                || appState.pendingNotificationRoute?.chatRouteScopeKey == dismissedScopeKey
                || notificationNavigationQueue.contains(where: { $0.route.chatRouteScopeKey == dismissedScopeKey }) {
                Logger(category: "ChatNavigation").warning("[ChatNavigation] dismiss residualChatRoute roomId=\(dismissedRoomId)")
            }
        }
        Logger(category: "ChatNavigation").debug("[ChatNavigation] pop completed remainingTop=nil")
        Logger(category: "ChatNavigation").debug("[ChatNavigation] state cleared selectedRoom=false pendingDeepLink=false activeRoomId=nil")
    }

    private func targetTab(for route: AppNotificationRoute) -> RootTab {
        switch route {
        case .orderDetail, .orderList, .paymentReceipt:
            return .order
        case .communityPost, .communityList:
            return .community
        case .videoDetail, .shorts:
            return .video
        case .storeDetail, .cart:
            return .home
        case .chatRoom, .profile, .none:
            return .profile
        }
    }

    private func logInitialTabReloadIfNeeded() {
#if DEBUG
        guard !didLogInitialTabReload else { return }
        didLogInitialTabReload = true
        logTabReload(tab: appState.selectedTab, reason: "initial")
#endif
    }

    private func logTabSwitch(from previousTab: RootTab, to tab: RootTab) {
#if DEBUG
        Logger(category: "Tab").debug("[TabSwitch] from=\(previousTab.rawValue) to=\(tab.rawValue)")
#endif
    }

    private func logTabReload(tab: RootTab, reason: String) {
#if DEBUG
        Logger(category: "Tab").debug("[TabReload] tab=\(tab.rawValue) reason=\(reason)")
#endif
    }

    private static func isCurrentMainThreadForLog() -> Bool {
        pthread_main_np() == 1
    }

    private static func chatRouteScopeKey(roomId: String, storeId: String?) -> String {
        "store:\(storeId?.nilIfEmpty ?? "-")|room:\(roomId)"
    }
}

struct NotificationNavigationRequest: Equatable {
    let route: AppNotificationRoute
    let source: NotificationRouteSource
}

private struct NotificationChatPathRoute: Hashable {
    let roomID: String
    let storeID: String?
    let title: String
    let entryPoint: ChatRoomEntryPoint
    let roomScopeKey: String

    init(route: AppNotificationRoute, source: NotificationRouteSource) {
        if case .chatRoom(let roomID, let storeID, let title) = route {
            self.roomID = roomID
            self.storeID = storeID
            self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "채팅"
        } else {
            self.roomID = ""
            self.storeID = nil
            self.title = "채팅"
        }
        self.entryPoint = Self.chatEntryPoint(for: source)
        self.roomScopeKey = "store:\(self.storeID?.nilIfEmpty ?? "-")|room:\(self.roomID)"
    }

    var chatTarget: ChatTarget {
        .room(
            roomID: roomID,
            title: title,
            target: nil,
            source: entryPoint,
            storeID: storeID,
            opponentID: nil
        )
    }

    private static func chatEntryPoint(for source: NotificationRouteSource) -> ChatRoomEntryPoint {
        switch source {
        case .remoteFCM:
            return .remoteFCM
        case .localNotification:
            return .localNotification
        case .notificationCenter:
            return .deepLink
        case .appInternalDebug:
            return .unknown
        }
    }
}

private struct NotificationRoutePresentation: Identifiable {
    let id: String
    let route: AppNotificationRoute
    let source: NotificationRouteSource

    init(route: AppNotificationRoute, source: NotificationRouteSource) {
        self.route = route
        self.source = source
        self.id = route.presentationIdentity
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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

    var isChatRoute: Bool {
        if case .chatRoom = self {
            return true
        }
        return false
    }

    var isOrderRoute: Bool {
        switch self {
        case .orderDetail, .orderList, .paymentReceipt:
            return true
        case .chatRoom, .storeDetail, .videoDetail, .shorts, .communityPost, .communityList, .cart, .profile, .none:
            return false
        }
    }

    var orderRouteIdentifier: String? {
        switch self {
        case .orderDetail(let orderCode), .paymentReceipt(let orderCode):
            return orderCode
        case .orderList, .chatRoom, .storeDetail, .videoDetail, .shorts, .communityPost, .communityList, .cart, .profile, .none:
            return nil
        }
    }

    var presentationIdentity: String {
        switch self {
        case .chatRoom(let roomId, let storeId, _):
            return "globalRoot.chat.\(storeId?.nilIfEmpty ?? "-").\(roomId)"
        case .storeDetail(let storeId):
            return "globalRoot.store.\(storeId)"
        case .videoDetail(let videoId):
            return "globalRoot.video.\(videoId)"
        case .shorts(let videoId):
            return "globalRoot.shorts.\(videoId ?? "-")"
        case .orderDetail(let orderCode):
            return "globalRoot.order.\(orderCode)"
        case .paymentReceipt(let orderCode):
            return "globalRoot.payment.\(orderCode)"
        case .communityPost(let postId, let commentId):
            return "globalRoot.post.\(postId).\(commentId ?? "-")"
        case .orderList:
            return "globalRoot.orders"
        case .communityList:
            return "globalRoot.community"
        case .cart:
            return "globalRoot.cart"
        case .profile:
            return "globalRoot.profile"
        case .none:
            return "globalRoot.notificationCenter"
        }
    }
}

private extension AppNotificationRoute {
    var chatRouteScopeKey: String? {
        guard case .chatRoom(let roomId, let storeId, _) = self else {
            return nil
        }
        return "store:\(storeId?.nilIfEmpty ?? "-")|room:\(roomId)"
    }
}

@MainActor
private final class RootTabKeyboardObserver: ObservableObject {
    @Published private(set) var isKeyboardVisible = false
    @Published private(set) var animationDuration: Double = 0.25

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleKeyboardWillChangeFrame(_ notification: Notification) {
        updateKeyboardState(
            isVisible: keyboardOverlapHeight(from: notification) > 0,
            duration: animationDuration(from: notification),
            key: "rootTabKeyboard"
        )
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        updateKeyboardState(
            isVisible: false,
            duration: animationDuration(from: notification),
            key: "rootTabKeyboard"
        )
    }

    private func keyboardOverlapHeight(from notification: Notification) -> CGFloat {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }

        let windowBounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .bounds ?? UIScreen.main.bounds
        return max(0, windowBounds.maxY - endFrame.minY)
    }

    private func animationDuration(from notification: Notification) -> Double {
        notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    }

    private func updateKeyboardState(isVisible: Bool, duration: Double, key: String) {
        let didChange = isKeyboardVisible != isVisible || animationDuration != duration
        guard didChange else {
            #if DEBUG
            DebugLogDeduplicator.shared.printWhenChanged(
                key: "SwiftUIStateGuard.\(key)",
                value: "\(isVisible)|\(duration)",
                logger: Logger(category: "SwiftUIStateGuard"),
                message: "[SwiftUIStateGuard] dedupe layout update key=\(key)"
            )
            #endif
            return
        }
        animationDuration = duration
        isKeyboardVisible = isVisible
    }
}
