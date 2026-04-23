import Foundation

@MainActor
final class SessionRestorer {
    private let authRepository: AuthRepository
    private let sessionStore: SessionStore

    init(authRepository: AuthRepository, sessionStore: SessionStore) {
        self.authRepository = authRepository
        self.sessionStore = sessionStore
    }

    func restoreIfAvailable() async {
        do {
            let session = try await authRepository.restoreSession()
            sessionStore.apply(session: session)
        } catch {
            sessionStore.clear()
            Logger.shared.warning("Session restoration failed: \(error.localizedDescription)")
        }
    }
}
