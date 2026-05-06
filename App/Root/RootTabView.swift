import SwiftUI
import UIKit

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
    @State private var presentedNotificationRoute: NotificationRoutePresentation?
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
                RootTabContainerView(path: $homePath, isActive: appState.selectedTab == .home) {
                    featureBuilderFactory.makeHomeView(resetTrigger: homeResetTrigger)
                }

                RootTabContainerView(path: $orderPath, isActive: appState.selectedTab == .order) {
                    featureBuilderFactory.makeOrderView()
                }

                RootTabContainerView(path: $videoPath, isActive: appState.selectedTab == .video) {
                    featureBuilderFactory.makeVideoListView(resetTrigger: videoResetTrigger)
                }

                RootTabContainerView(path: $communityPath, isActive: appState.selectedTab == .community) {
                    featureBuilderFactory.makeCommunityView()
                }

                RootTabContainerView(path: $profilePath, isActive: appState.selectedTab == .profile) {
                    featureBuilderFactory.makeProfileView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.selectedTab)
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
        .onAppear {
            featureBuilderFactory.routePendingNotificationIfNeeded()
            handleNotificationRoute(appState.pendingNotificationRoute)
        }
        .onChange(of: appState.pendingNotificationRoute) { _, route in
            handleNotificationRoute(route)
        }
    }

    private func handleTabSelection(_ tab: RootTab) {
        if tab == .home {
            homePath = NavigationPath()
            homeResetTrigger += 1
        }

        if tab == .video {
            videoPath = NavigationPath()
            videoResetTrigger += 1
        }

        appState.selectedTab = tab
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

    private func handleNotificationRoute(_ route: AppNotificationRoute?) {
        guard let route else { return }

        switch route {
        case .orderList:
            appState.selectedTab = .order
        case .communityList:
            appState.selectedTab = .community
        case .orderDetail:
            appState.selectedTab = .order
            appState.activeNotificationRoute = route
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
        case .paymentReceipt:
            appState.selectedTab = .order
            appState.activeNotificationRoute = route
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
        case .chatRoom:
            appState.selectedTab = .profile
            appState.activeNotificationRoute = route
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
        case .communityPost:
            appState.selectedTab = .community
            appState.activeNotificationRoute = route
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
        case .none:
            appState.selectedTab = .profile
            appState.activeNotificationRoute = route
            presentedNotificationRoute = NotificationRoutePresentation(route: route)
        }

        appState.pendingNotificationRoute = nil
    }
}

private struct NotificationRoutePresentation: Identifiable {
    let id = UUID()
    let route: AppNotificationRoute
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
