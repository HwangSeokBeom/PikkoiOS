import SwiftUI

struct RootScene: View {
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
            await bootstrapper.bootstrapIfNeeded()
        }
        .task(id: sessionStore.deviceTokenSyncStateID) {
            guard sessionStore.isAuthenticated else { return }
            await featureBuilderFactory.syncCurrentDeviceTokenIfNeeded()
        }
    }
}

private struct SplashScreenView: View {
    var body: some View {
        GeometryReader { proxy in
            Image("SplashScreen")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .background(PikkoColor.sage50)
        .ignoresSafeArea()
    }
}
