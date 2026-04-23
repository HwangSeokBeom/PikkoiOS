import Foundation

@MainActor
final class SessionStore: ObservableObject {
    enum AuthState: Equatable {
        case authenticated
        case unauthenticated
    }

    private enum StorageKey {
        static let deviceToken = "session.deviceToken"
    }

    @Published private(set) var currentSession: UserSession?
    @Published private(set) var deviceToken: String?
    private let tokenStore: any TokenStore
    private let userDefaultsStore: any UserDefaultsStoring
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

    var nick: String? {
        currentSession?.nick
    }

    var profileImagePath: String? {
        currentSession?.profileImagePath
    }

    var isAuthenticated: Bool {
        currentSession != nil
    }

    var authState: AuthState {
        isAuthenticated ? .authenticated : .unauthenticated
    }

    init(
        tokenStore: any TokenStore,
        userDefaultsStore: any UserDefaultsStoring
    ) {
        self.tokenStore = tokenStore
        self.userDefaultsStore = userDefaultsStore
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
        }
    }

    func updateProfile(
        nick: String? = nil,
        profileImagePath: String? = nil
    ) {
        guard let currentSession else { return }
        self.currentSession = UserSession(
            userID: currentSession.userID,
            displayName: nick ?? currentSession.displayName,
            profileImagePath: profileImagePath ?? currentSession.profileImagePath,
            accessToken: currentSession.accessToken,
            refreshToken: currentSession.refreshToken
        )
    }

    func updateDeviceToken(_ deviceToken: String?) {
        self.deviceToken = deviceToken
        userDefaultsStore.set(deviceToken, forKey: StorageKey.deviceToken)
    }

    func clear() {
        currentSession = nil
        Task {
            try? await tokenStore.clearTokens()
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
}
