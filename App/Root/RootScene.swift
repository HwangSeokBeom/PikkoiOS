import SwiftUI

struct RootScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var appState: AppState
    @ObservedObject private var sessionStore: SessionStore

    private let bootstrapper: AppBootstrapper
    private let featureBuilderFactory: FeatureBuilderFactory

    init(
        appState: AppState,
        bootstrapper: AppBootstrapper,
        featureBuilderFactory: FeatureBuilderFactory
    ) {
        _appState = ObservedObject(wrappedValue: appState)
        _sessionStore = ObservedObject(wrappedValue: appState.sessionStore)
        self.bootstrapper = bootstrapper
        self.featureBuilderFactory = featureBuilderFactory
    }

    var body: some View {
        Group {
            switch appState.launchPhase {
            case .idle, .restoringSession:
                SplashScreenView()
            case .ready:
                if sessionStore.isAuthenticated {
                    RootTabView(
                        appState: appState,
                        featureBuilderFactory: featureBuilderFactory
                    )
                } else {
                    AuthGateView(
                        featureBuilderFactory: featureBuilderFactory
                    )
                }
            }
        }
        .task {
            Logger(category: "AppLifecycle").debug("[AppLifecycle] scene willConnect")
            featureBuilderFactory.setNotificationSceneReady(true)
            featureBuilderFactory.setNotificationSceneActive(scenePhase == .active)
            featureBuilderFactory.registerOrderBackgroundRefresh()
            await bootstrapper.bootstrapIfNeeded()
            featureBuilderFactory.routePendingNotificationIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Logger(category: "AppLifecycle").debug("[AppLifecycle] sceneDidBecomeActive")
                featureBuilderFactory.setNotificationSceneActive(true)
                Task {
                    await featureBuilderFactory.refreshOrdersForSystemState(source: .foreground, force: true)
                }
            case .inactive:
                Logger(category: "AppLifecycle").debug("[AppLifecycle] sceneDidBecomeInactive")
                featureBuilderFactory.setNotificationSceneActive(false)
            case .background:
                Logger(category: "AppLifecycle").debug("[AppLifecycle] sceneDidEnterBackground")
                featureBuilderFactory.setNotificationSceneActive(false)
                featureBuilderFactory.scheduleOrderBackgroundRefresh()
            @unknown default:
                Logger(category: "AppLifecycle").debug("[AppLifecycle] scenePhaseUnknown")
            }
        }
        .task(id: sessionStore.deviceTokenSyncStateID) {
            guard sessionStore.isAuthenticated else { return }
            await featureBuilderFactory.syncCurrentDeviceTokenIfNeeded()
        }
        .onChange(of: sessionStore.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            PikkoAppDelegate.fetchCurrentFCMTokenForAuthenticatedSession()
            Task {
                await featureBuilderFactory.syncCurrentDeviceTokenIfNeeded(source: "authStateChanged")
            }
            featureBuilderFactory.routePendingNotificationIfNeeded()
        }
        .onChange(of: appState.pendingDeepLink) { _, url in
            guard let url else { return }
            featureBuilderFactory.routeDeepLink(url)
            appState.pendingDeepLink = nil
        }
    }
}

private struct SplashScreenView: View {
    var body: some View {
        PikkoColor.background
            .ignoresSafeArea()
    }
}
