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
            guard let session else {
                await sessionStore.clearSession()
                Logger.shared.info("No valid stored session. Presenting authentication gate.")
                return
            }
            await sessionStore.establishAuthenticatedSession(session)
        } catch {
            await sessionStore.clearSession()
            Logger.shared.warning("Session restoration failed: \(error.localizedDescription)")
        }
    }
}
