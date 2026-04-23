import SwiftUI

@main
struct PikkoApp: App {
    private let container: AppDIContainer
    private let bootstrapper: AppBootstrapper
    private let featureBuilderFactory: FeatureBuilderFactory

    @StateObject private var appState: AppState

    init() {
        let container = AppDIContainer()
        let appState = container.makeAppState()

        self.container = container
        self.bootstrapper = container.makeAppBootstrapper(appState: appState)
        self.featureBuilderFactory = container.makeFeatureBuilderFactory(appState: appState)
        _appState = StateObject(wrappedValue: appState)
    }

    var body: some Scene {
        WindowGroup {
            RootScene(
                appState: appState,
                bootstrapper: bootstrapper,
                featureBuilderFactory: featureBuilderFactory
            )
            .environmentObject(appState)
            .environmentObject(appState.sessionStore)
            .environmentObject(appState.cartStore)
        }
    }
}
