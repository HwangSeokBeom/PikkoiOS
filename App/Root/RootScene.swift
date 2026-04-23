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
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    LoadingView(message: "세션을 준비하고 있어요")
                        .padding(PikkoSpacing.xl)
                }
            case .ready:
                if sessionStore.isAuthenticated {
                    RootTabView(
                        appState: appState,
                        featureBuilderFactory: featureBuilderFactory
                    )
                } else {
                    AuthGateView(featureBuilderFactory: featureBuilderFactory)
                }
            }
        }
        .task {
            await bootstrapper.bootstrapIfNeeded()
        }
    }
}
