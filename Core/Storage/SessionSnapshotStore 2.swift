import Foundation

struct StoredSessionProfile: Codable, Equatable, Sendable {
    let userID: String
    let email: String?
    let displayName: String
    let profileImagePath: String?

    init(session: UserSession) {
        self.userID = session.userID
        self.email = session.email
        self.displayName = session.displayName
        self.profileImagePath = session.profileImagePath
    }

    func makeSession(tokens: StoredTokens) -> UserSession {
        UserSession(
            userID: userID,
            email: email,
            displayName: displayName,
            profileImagePath: profileImagePath,
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken
        )
    }
}

protocol SessionSnapshotStoring: Sendable {
    func loadSnapshot() async -> StoredSessionProfile?
    func saveSnapshot(_ snapshot: StoredSessionProfile?) async throws
}

actor UserDefaultsSessionSnapshotStore: SessionSnapshotStoring {
    private enum StorageKey {
        static let sessionProfile = "session.profile"
    }

    private let store: any UserDefaultsStoring

    init(store: any UserDefaultsStoring) {
        self.store = store
    }

    func loadSnapshot() async -> StoredSessionProfile? {
        store.codableValue(StoredSessionProfile.self, forKey: StorageKey.sessionProfile)
    }

    func saveSnapshot(_ snapshot: StoredSessionProfile?) async throws {
        try store.setCodable(snapshot, forKey: StorageKey.sessionProfile)
    }
}
