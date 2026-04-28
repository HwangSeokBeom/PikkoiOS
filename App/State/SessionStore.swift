import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum AuthState: Equatable {
        case authenticated
        case unauthenticated
    }

    private enum StorageKey {
        static let deviceToken = "session.deviceToken"
        static let lastSyncedDeviceTokenSignature = "session.lastSyncedDeviceTokenSignature"
    }

    @Published private(set) var currentSession: UserSession?
    @Published private(set) var deviceToken: String?
    private let tokenStore: any TokenStore
    private let userDefaultsStore: any UserDefaultsStoring
    private let sessionSnapshotStore: any SessionSnapshotStoring
    private var notificationObservers: [NSObjectProtocol] = []

    var accessToken: String? {
        currentSession?.accessToken
    }

    var refreshToken: String? {
        currentSession?.refreshToken
    }

    var currentUserID: String? {
        currentSession?.userID
    }

    var email: String? {
        currentSession?.email
    }

    var nick: String? {
        currentSession?.nick
    }

    var profileImagePath: String? {
        currentSession?.profileImagePath
    }

    var isAuthenticated: Bool {
        currentSession != nil
    }

    var deviceTokenSyncStateID: String {
        [currentUserID ?? "guest", deviceToken ?? "none", authState == .authenticated ? "auth" : "anon"]
            .joined(separator: "|")
    }

    var hasSyncedCurrentDeviceToken: Bool {
        currentDeviceTokenSignature != nil
            && currentDeviceTokenSignature == userDefaultsStore.string(forKey: StorageKey.lastSyncedDeviceTokenSignature)
    }

    var authState: AuthState {
        isAuthenticated ? .authenticated : .unauthenticated
    }

    init(
        tokenStore: any TokenStore,
        userDefaultsStore: any UserDefaultsStoring,
        sessionSnapshotStore: (any SessionSnapshotStoring)? = nil
    ) {
        self.tokenStore = tokenStore
        self.userDefaultsStore = userDefaultsStore
        self.sessionSnapshotStore = sessionSnapshotStore ?? UserDefaultsSessionSnapshotStore(store: userDefaultsStore)
        self.deviceToken = userDefaultsStore.string(forKey: StorageKey.deviceToken)
        bindNetworkNotifications()
    }

    func apply(session: UserSession?) {
        guard let session else {
            clear()
            return
        }

        currentSession = session
        Task {
            try? await tokenStore.saveTokens(
                StoredTokens(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken
                )
            )
            try? await sessionSnapshotStore.saveSnapshot(StoredSessionProfile(session: session))
        }
    }

    @discardableResult
    func establishAuthenticatedSession(_ session: UserSession) async -> Bool {
        do {
            try await tokenStore.saveTokens(
                StoredTokens(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken
                )
            )
            try await sessionSnapshotStore.saveSnapshot(StoredSessionProfile(session: session))
            Logger.shared.debug("[Auth] token save completed")
        } catch {
            Logger.shared.warning("[Auth] token save failed: \(error.localizedDescription)")
            currentSession = nil
            clearSyncedDeviceTokenState()
            return false
        }

        currentSession = session
        Logger.shared.debug("[Auth] auth state changed authenticated")
        return true
    }

    func prepareForLoginAttempt() async {
        guard !isAuthenticated else { return }
        clearSyncedDeviceTokenState()

        do {
            try await tokenStore.clearTokens()
        } catch {
            Logger.shared.warning("[Auth] stale session cleanup failed: \(error.localizedDescription)")
        }

        do {
            try await sessionSnapshotStore.saveSnapshot(nil)
        } catch {
            Logger.shared.warning("[Auth] stale session snapshot cleanup failed: \(error.localizedDescription)")
        }
    }

    func clearSession() async {
        currentSession = nil
        clearSyncedDeviceTokenState()

        do {
            try await tokenStore.clearTokens()
        } catch {
            Logger.shared.warning("[Auth] session clear failed: \(error.localizedDescription)")
        }

        do {
            try await sessionSnapshotStore.saveSnapshot(nil)
        } catch {
            Logger.shared.warning("[Auth] session snapshot clear failed: \(error.localizedDescription)")
        }
    }

    func updateProfile(
        nick: String? = nil,
        profileImagePath: String? = nil
    ) {
        guard let currentSession else { return }
        self.currentSession = UserSession(
            userID: currentSession.userID,
            email: currentSession.email,
            displayName: nick ?? currentSession.displayName,
            profileImagePath: profileImagePath ?? currentSession.profileImagePath,
            accessToken: currentSession.accessToken,
            refreshToken: currentSession.refreshToken
        )
        if let currentSession = self.currentSession {
            Task {
                try? await sessionSnapshotStore.saveSnapshot(StoredSessionProfile(session: currentSession))
            }
        }
    }

    func updateDeviceToken(_ deviceToken: String?) {
        self.deviceToken = deviceToken
        userDefaultsStore.set(deviceToken, forKey: StorageKey.deviceToken)
    }

    func markCurrentDeviceTokenSynced() {
        userDefaultsStore.set(currentDeviceTokenSignature, forKey: StorageKey.lastSyncedDeviceTokenSignature)
    }

    func clearSyncedDeviceTokenState() {
        userDefaultsStore.removeValue(forKey: StorageKey.lastSyncedDeviceTokenSignature)
    }

    func clear() {
        currentSession = nil
        clearSyncedDeviceTokenState()
        Task {
            try? await tokenStore.clearTokens()
            try? await sessionSnapshotStore.saveSnapshot(nil)
        }
    }

    private func bindNetworkNotifications() {
        let center = NotificationCenter.default

        notificationObservers.append(
            center.addObserver(
                forName: .pikkoSessionDidInvalidate,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.currentSession = nil
                    self?.clearSyncedDeviceTokenState()
                }
            }
        )

        notificationObservers.append(
            center.addObserver(
                forName: .pikkoTokensDidRefresh,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let accessToken = notification.userInfo?[NetworkSessionNotificationUserInfoKey.accessToken] as? String
                let refreshToken = notification.userInfo?[NetworkSessionNotificationUserInfoKey.refreshToken] as? String

                Task { @MainActor [weak self] in
                    guard let self,
                          let accessToken,
                          let refreshToken,
                          let currentSession = self.currentSession else {
                        return
                    }

                    self.currentSession = currentSession.updatingTokens(
                        accessToken: accessToken,
                        refreshToken: refreshToken
                    )
                }
            }
        )
    }

    private var currentDeviceTokenSignature: String? {
        guard let currentUserID,
              let deviceToken,
              !deviceToken.isEmpty else {
            return nil
        }

        return "\(currentUserID)|\(deviceToken)"
    }
}

@MainActor
protocol DeviceTokenProviding: AnyObject {
    var currentDeviceToken: String? { get }
}

extension SessionStore: DeviceTokenProviding {
    var currentDeviceToken: String? {
        deviceToken
    }
}
