import SwiftUI
import UIKit

struct RootTabView: View {
    @ObservedObject private var appState: AppState
    let featureBuilderFactory: FeatureBuilderFactory

    @State private var homePath = NavigationPath()
    @State private var orderPath = NavigationPath()
    @State private var communityPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var homeResetTrigger = 0
    @State private var isQuickActionPresented = false
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
                    },
                    onQuickAction: {
                        isQuickActionPresented = true
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            .easeOut(duration: keyboardObserver.animationDuration),
            value: keyboardObserver.isKeyboardVisible
        )
        .sheet(isPresented: $isQuickActionPresented) {
            NavigationStack {
                featureBuilderFactory.makeCartView()
            }
        }
    }

    private func handleTabSelection(_ tab: RootTab) {
        if tab == .home {
            homePath = NavigationPath()
            homeResetTrigger += 1
        }

        appState.selectedTab = tab
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
