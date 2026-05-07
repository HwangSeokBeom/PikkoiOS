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
    @State private var notificationNavigationQueue: [AppNotificationRoute] = []
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
                    featureBuilderFactory.makeVideoListView(resetTrigger: videoResetTrigger)
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
                RootTabBarView(
                    selectedTab: appState.selectedTab,
                    onSelect: { tab in
                        handleTabSelection(tab)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            .easeOut(duration: keyboardObserver.animationDuration),
            value: keyboardObserver.isKeyboardVisible
        )
        .sheet(item: $presentedNotificationRoute, onDismiss: {
            appState.activeNotificationRoute = nil
        }) { presentation in
            NavigationStack {
                destinationView(for: presentation.route)
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
            logInitialTabReloadIfNeeded()
            featureBuilderFactory.setNotificationNavigationReady(true)
            featureBuilderFactory.routePendingNotificationIfNeeded()
            scheduleNotificationRoute(appState.pendingNotificationRoute)
        }
        .onDisappear {
            featureBuilderFactory.setNotificationNavigationReady(false)
        }
        .onChange(of: appState.pendingNotificationRoute) { _, route in
            scheduleNotificationRoute(route)
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
    private func destinationView(for route: AppNotificationRoute) -> some View {
        switch route {
        case .orderDetail(let orderCode), .paymentReceipt(let orderCode):
            featureBuilderFactory.makeOrderDetailView(orderID: orderCode)
        case .chatRoom(let roomId, _, let title):
            featureBuilderFactory.makeChatView(target: .room(roomID: roomId, title: title ?? "채팅", target: nil))
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

    private func scheduleNotificationRoute(_ route: AppNotificationRoute?) {
        guard let route else { return }
        Task { @MainActor in
            await Task.yield()
            enqueueNotificationRoute(route)
        }
    }

    private func enqueueNotificationRoute(_ route: AppNotificationRoute) {
        guard !notificationNavigationQueue.contains(route) else {
            Logger(category: "NavigationQueue").debug("[NavigationQueue] deferred reason=duplicatePending route=\(route.logRouteName) \(route.logIdentifier)")
            return
        }

        notificationNavigationQueue.append(route)
        Logger(category: "NavigationQueue").debug("[NavigationQueue] enqueue route=\(route.logRouteName) \(route.logIdentifier) source=remoteFCM")
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
                let route = notificationNavigationQueue.removeFirst()
                let didComplete = await performNotificationNavigation(route)
                if !didComplete {
                    didDeferRoute = true
                    break
                }
            }
        }
    }

    @discardableResult
    private func performNotificationNavigation(_ route: AppNotificationRoute) async -> Bool {
        guard appState.launchPhase == .ready, appState.sessionStore.isAuthenticated else {
            notificationNavigationQueue.insert(route, at: 0)
            Logger(category: "NavigationQueue").debug("[NavigationQueue] deferred reason=authNotReady route=\(route.logRouteName) \(route.logIdentifier)")
            return false
        }

        let targetTab = targetTab(for: route)
        if appState.selectedTab != targetTab {
            let previousTab = appState.selectedTab
            Logger(category: "NavigationQueue").debug("[NavigationQueue] selectTab target=\(targetTab.rawValue) previous=\(previousTab.rawValue) route=\(route.logRouteName)")
            appState.selectedTab = targetTab
            await Task.yield()
        }

        guard appState.selectedTab == targetTab else {
            notificationNavigationQueue.insert(route, at: 0)
            Logger(category: "NavigationQueue").debug("[NavigationQueue] deferred reason=targetTabNotReady route=\(route.logRouteName) \(route.logIdentifier)")
            return false
        }

        Logger(category: "NavigationQueue").debug("[NavigationQueue] targetReady tab=\(targetTab.rawValue)")

        switch route {
        case .orderList:
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=orders")
        case .communityList:
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=community")
        case .orderDetail:
            appState.activeNotificationRoute = route
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=order")
        case .paymentReceipt:
            appState.activeNotificationRoute = route
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=order")
        case .chatRoom:
            guard case .chatRoom(let roomId, _, _) = route, !roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger(category: "DeepLink").error("[DeepLink] navigate failed reason=missingRoomId route=chat")
                Logger(category: "NavigationQueue").error("[NavigationQueue] failed route=chat roomId=- reason=missingRoomId")
                return true
            }
            appState.activeNotificationRoute = route
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
            Logger(category: "NavigationQueue").info("[NavigationQueue] push route=chat roomId=\(roomId) tab=\(targetTab.rawValue)")
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=chat")
        case .communityPost:
            appState.activeNotificationRoute = route
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate success destination=post")
        case .none:
            appState.activeNotificationRoute = route
            await Task.yield()
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
            Logger(category: "PushDeepLink").debug("[PushDeepLink] navigate fallback destination=notificationCenter reason=noCustomData")
        }

        appState.pendingNotificationRoute = nil
        Logger(category: "NavigationQueue").debug("[NavigationQueue] complete route=\(route.logRouteName) \(route.logIdentifier)")
        return true
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

private struct NotificationRoutePresentation: Identifiable {
    let id = UUID()
    let route: AppNotificationRoute
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
