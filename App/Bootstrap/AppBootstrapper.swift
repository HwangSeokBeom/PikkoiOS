import Foundation

@MainActor
final class AppBootstrapper: ObservableObject {
    private let appState: AppState
    private let sessionRestorer: SessionRestorer
    private var hasBootstrapped = false

    init(appState: AppState, sessionRestorer: SessionRestorer) {
        self.appState = appState
        self.sessionRestorer = sessionRestorer
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        appState.launchPhase = .restoringSession
        await sessionRestorer.restoreIfAvailable()
        await appState.cartStore.refresh(for: appState.sessionStore.currentSession)
        appState.launchPhase = .ready
    }
}
