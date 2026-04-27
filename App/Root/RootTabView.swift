import SwiftUI

struct RootTabView: View {
    @ObservedObject private var appState: AppState
    let featureBuilderFactory: FeatureBuilderFactory

    @State private var homePath = NavigationPath()
    @State private var orderPath = NavigationPath()
    @State private var communityPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var homeResetTrigger = 0
    @State private var isQuickActionPresented = false

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
            RootTabBarView(
                selectedTab: appState.selectedTab,
                onSelect: { tab in
                    handleTabSelection(tab)
                },
                onQuickAction: {
                    isQuickActionPresented = true
                }
            )
        }
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
