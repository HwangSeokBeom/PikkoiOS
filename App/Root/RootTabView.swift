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
    @State private var currentPresentedChatRoomId: String?
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
        case .chatRoom(let roomId, _, let title):
            featureBuilderFactory.makeChatView(target: .room(
                roomID: roomId,
                title: title ?? "채팅",
                target: nil,
                source: chatEntryPoint(for: source),
                storeID: route.chatStoreId,
                opponentID: nil
            ), presentationKind: .globalSheet)
        case .communityPost(let postId, let commentId):
            featureBuilderFactory.makeCommunityDetailView(postID: postId, initialCommentID: commentId)
        case .orderList:
            featureBuilderFactory.makeOrderView()
        case .communityList:
            featureBuilderFactory.makeCommunityView()
        case .none:
            featureBuilderFactory.makeNotificationListView()
        }
    }

    private func scheduleNotificationRoute(_ route: AppNotificationRoute?, source: NotificationRouteSource?) {
        guard let route else { return }
        Task { @MainActor in
            await Task.yield()
            enqueueNotificationRoute(route, source: source ?? .remoteFCM)
        }
    }

    private func enqueueNotificationRoute(_ route: AppNotificationRoute, source: NotificationRouteSource) {
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
        guard appState.launchPhase == .ready, appState.sessionStore.isAuthenticated else {
            notificationNavigationQueue.insert(NotificationNavigationRequest(route: route, source: source), at: 0)
            Logger(category: "NavigationQueue").debug("[NavigationQueue] deferred reason=authNotReady route=\(route.logRouteName) \(route.logIdentifier)")
            return false
        }

        let targetTab = targetTab(for: route)
        Logger(category: "ChatRouteOwner").debug("[ChatRouteOwner] policy=\(route.isChatRoute ? "globalRoot" : "profileStack") reason=\(route.isChatRoute ? "chatPushPresentedAtRoot" : "tabOwnedRoute")")
        Logger(category: "ChatRouteOwner").debug("[ChatRouteOwner] previousSelectedTab=\(appState.selectedTab.rawValue) targetTab=\(targetTab.rawValue)")
        Logger(category: "ChatRouteOwner").debug("[ChatRouteOwner] preserveReturnTab=\(route.isChatRoute)")

        if !route.isChatRoute, appState.selectedTab != targetTab {
            let previousTab = appState.selectedTab
            Logger(category: "NavigationQueue").debug("[NavigationQueue] selectTab target=\(targetTab.rawValue) previous=\(previousTab.rawValue) route=\(route.logRouteName)")
            appState.selectedTab = targetTab
            await Task.yield()
        }

        guard route.isChatRoute || appState.selectedTab == targetTab else {
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
            guard case .chatRoom(let roomId, _, _) = route, !roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger(category: "DeepLink").error("[DeepLink] navigate failed reason=missingRoomId route=chat")
                Logger(category: "NavigationQueue").error("[NavigationQueue] failed route=chat roomId=- reason=missingRoomId")
                return true
            }
            Logger(category: "ChatNavigation").debug("[ChatNavigation] open requested roomId=\(roomId) source=\(source.rawValue)")
            let sheetRouteBefore = presentedNotificationRoute?.route
            let pathCountBefore = profilePath.count
            let decision = AppNotificationRouter.ChatPresentationReducer.reduce(
                incomingRoute: route,
                currentSheetRoute: sheetRouteBefore,
                currentPresentedChatRoomId: currentPresentedChatRoomId,
                pendingRoute: appState.pendingNotificationRoute,
                navigationQueue: notificationNavigationQueue.map(\.route)
            )
            if decision.removedQueuedDuplicateCount > 0 {
                let existingIndex = notificationNavigationQueue.firstIndex { $0.route.chatRoomId == roomId } ?? 0
                notificationNavigationQueue.removeAll { $0.route.chatRoomId == roomId }
                Logger(category: "ChatNavigation").warning("[ChatNavigation] duplicate prevented roomId=\(roomId) existingIndex=\(existingIndex)")
            }
            Logger(category: "ChatNavigation").debug(
                "[ChatNavigation] before currentSheetRoute=\(sheetRouteBefore?.debugDescription ?? "nil") currentPresentedChatRoomId=\(currentPresentedChatRoomId ?? "nil") incomingRoomId=\(roomId) action=\(decision.action.rawValue)"
            )
            Logger(category: "NavigationPath").debug(
                "[NavigationPath] beforeCount=\(pathCountBefore) afterCount=\(profilePath.count) appendedRoute=none removedDuplicateCount=0"
            )
            let isSameRoomAlreadyPresented = (currentPresentedChatRoomId ?? sheetRouteBefore?.chatRoomId) == roomId
            if decision.action == .skip || (decision.action == .clearDuplicate && isSameRoomAlreadyPresented) {
                Logger(category: "ChatNavigation").debug("[ChatNavigation] open skipped reason=alreadyTop roomId=\(roomId)")
                appState.pendingNotificationRoute = nil
                appState.pendingNotificationRouteSource = nil
                Logger(category: "NavigationQueue").debug("[NavigationQueue] pendingRoute cleared reason=chatSkip roomId=\(roomId)")
                return true
            }
            if decision.action == .replace {
                Logger(category: "ChatNavigation").debug("[ChatNavigation] replace reason=existingChatRoute roomId=\(roomId)")
                presentedNotificationRoute = nil
                currentPresentedChatRoomId = nil
                await Task.yield()
            } else if decision.action == .clearDuplicate {
                Logger(category: "ChatNavigation").debug("[ChatNavigation] clearDuplicate roomId=\(roomId) removedQueuedDuplicateCount=\(decision.removedQueuedDuplicateCount)")
            }
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            currentPresentedChatRoomId = roomId
            Logger(category: "ChatNavigation").debug("[ChatNavigation] stackAfter count=1 chatRouteCount=1")
            Logger(category: "ChatNavigation").debug(
                "[ChatNavigation] after currentSheetRoute=\(presentedNotificationRoute?.route.debugDescription ?? "nil") currentPresentedChatRoomId=\(currentPresentedChatRoomId ?? "nil") incomingRoomId=\(roomId) action=\(decision.action.rawValue)"
            )
            Logger(category: "NavigationQueue").info("[NavigationQueue] set route=chat roomId=\(roomId) tab=globalRoot")
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=chat")
        case .communityPost:
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=post")
        case .none:
            appState.activeNotificationRoute = route
            appState.activeNotificationRouteSource = source
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route, source: source)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate fallback destination=notificationCenter reason=noCustomData")
        }

        appState.pendingNotificationRoute = nil
        appState.pendingNotificationRouteSource = nil
        Logger(category: "NavigationQueue").debug("[NavigationQueue] pendingRoute cleared reason=complete route=\(route.logRouteName) \(route.logIdentifier)")
        Logger(category: "NavigationQueue").debug("[NavigationQueue] complete route=\(route.logRouteName) \(route.logIdentifier)")
        return true
    }

    private func handleNotificationPresentationDismissed() {
        let dismissedRoomId = currentPresentedChatRoomId ?? presentedNotificationRoute?.route.chatRoomId
        Logger(category: "ChatNavigation").debug("[ChatNavigation] pop requested reason=presentationDismissed top=\(dismissedRoomId ?? "nil")")
        appState.activeNotificationRoute = nil
        appState.activeNotificationRouteSource = nil
        presentedNotificationRoute = nil
        currentPresentedChatRoomId = nil

        if let dismissedRoomId {
            let removedQueuedCount = notificationNavigationQueue.count
            notificationNavigationQueue.removeAll { $0.route.chatRoomId == dismissedRoomId }
            let removedCount = removedQueuedCount - notificationNavigationQueue.count
            if appState.pendingNotificationRoute?.chatRoomId == dismissedRoomId {
                appState.pendingNotificationRoute = nil
                appState.pendingNotificationRouteSource = nil
            }
            Logger(category: "ChatNavigation").debug(
                "[ChatNavigation] dismiss roomId=\(dismissedRoomId) clearedGlobalRoute=true clearedCurrentPresented=true removedQueuedCount=\(removedCount)"
            )
            if presentedNotificationRoute?.route.chatRoomId == dismissedRoomId
                || currentPresentedChatRoomId == dismissedRoomId
                || appState.pendingNotificationRoute?.chatRoomId == dismissedRoomId
                || notificationNavigationQueue.contains(where: { $0.route.chatRoomId == dismissedRoomId }) {
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
        case .chatRoom, .none:
            return .profile
        }
    }

    private func chatEntryPoint(for source: NotificationRouteSource?) -> ChatRoomEntryPoint {
        switch source {
        case .remoteFCM:
            return .remoteFCM
        case .localNotification:
            return .localNotification
        case .notificationCenter:
            return .deepLink
        case .appInternalDebug:
            return .unknown
        case nil:
            return .unknown
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
}

struct NotificationNavigationRequest: Equatable {
    let route: AppNotificationRoute
    let source: NotificationRouteSource
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
        case .chatRoom, .communityPost, .communityList, .none:
            return false
        }
    }

    var orderRouteIdentifier: String? {
        switch self {
        case .orderDetail(let orderCode), .paymentReceipt(let orderCode):
            return orderCode
        case .orderList, .chatRoom, .communityPost, .communityList, .none:
            return nil
        }
    }

    var chatRoomId: String? {
        if case .chatRoom(let roomId, _, _) = self {
            return roomId
        }
        return nil
    }

    var chatStoreId: String? {
        if case .chatRoom(_, let storeId, _) = self {
            return storeId
        }
        return nil
    }

    var presentationIdentity: String {
        switch self {
        case .chatRoom(let roomId, _, _):
            return "globalRoot.chat.\(roomId)"
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
        case .none:
            return "globalRoot.notificationCenter"
        }
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
        animationDuration = animationDuration(from: notification)
        isKeyboardVisible = keyboardOverlapHeight(from: notification) > 0
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        animationDuration = animationDuration(from: notification)
        isKeyboardVisible = false
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
}
