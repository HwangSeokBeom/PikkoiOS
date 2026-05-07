import Foundation

@MainActor
protocol ActiveChatRoomTracking: AnyObject {
    var activeRoomId: String? { get set }
}

@MainActor
final class ActiveChatRoomTracker: ActiveChatRoomTracking {
    var activeRoomId: String?
}

@MainActor
protocol ActiveCommunityPostTracking: AnyObject {
    var activePostId: String? { get set }
}

@MainActor
final class ActiveCommunityPostTracker: ActiveCommunityPostTracking {
    var activePostId: String?
}

@MainActor
final class PendingNotificationRouteStore {
    var pendingRoute: AppNotificationRoute?
    var pendingMessageId: String?
    var pendingSource: NotificationRouteSource?
    var pendingDedupeKey: String?

    func store(
        route: AppNotificationRoute,
        messageId: String?,
        source: NotificationRouteSource,
        dedupeKey: String
    ) {
        pendingRoute = route
        pendingMessageId = messageId
        pendingSource = source
        pendingDedupeKey = dedupeKey
    }

    func clear() {
        pendingRoute = nil
        pendingMessageId = nil
        pendingSource = nil
        pendingDedupeKey = nil
    }
}

enum PushNotificationDedupePhase: String {
    case save
    case read
    case navigate
}

@MainActor
final class PushNotificationDedupeStore {
    private var acceptedKeys: [String: Date] = [:]
    private let ttl: TimeInterval
    private let now: () -> Date

    init(ttl: TimeInterval = 30, now: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    func accept(key: String, phase: PushNotificationDedupePhase) -> Bool {
        pruneExpiredKeys()
        let currentDate = now()
        if let acceptedAt = acceptedKeys[key],
           currentDate.timeIntervalSince(acceptedAt) < ttl {
            Logger(category: "PushDedupe").debug("[PushDedupe] duplicate ignored key=\(key) phase=\(phase.rawValue)")
            return false
        }

        acceptedKeys[key] = currentDate
        Logger(category: "PushDedupe").debug("[PushDedupe] accepted key=\(key) phase=\(phase.rawValue)")
        return true
    }

    private func pruneExpiredKeys() {
        let currentDate = now()
        acceptedKeys = acceptedKeys.filter { currentDate.timeIntervalSince($0.value) < ttl }
    }
}

struct OrderStatusSnapshot: Codable, Equatable {
    let orderCode: String
    let status: String
    let updatedAt: Date
}

@MainActor
protocol OrderStatusSnapshotStore {
    func status(for orderCode: String) -> String?
    func saveStatus(_ status: String, for orderCode: String)
    func saveStatuses(_ statuses: [String: String])
    func count() -> Int
}

@MainActor
final class UserDefaultsOrderStatusSnapshotStore: OrderStatusSnapshotStore {
    private enum StorageKey {
        static let snapshots = "notification.orderStatusSnapshots"
    }

    private let store: any UserDefaultsStoring

    init(store: any UserDefaultsStoring) {
        self.store = store
    }

    func status(for orderCode: String) -> String? {
        snapshots()[orderCode]?.status
    }

    func saveStatus(_ status: String, for orderCode: String) {
        var values = snapshots()
        values[orderCode] = OrderStatusSnapshot(orderCode: orderCode, status: status, updatedAt: Date())
        persist(values)
    }

    func saveStatuses(_ statuses: [String: String]) {
        var values = snapshots()
        let now = Date()
        for (orderCode, status) in statuses {
            values[orderCode] = OrderStatusSnapshot(orderCode: orderCode, status: status, updatedAt: now)
        }
        persist(values)
    }

    func count() -> Int {
        snapshots().count
    }

    private func snapshots() -> [String: OrderStatusSnapshot] {
        store.codableValue([String: OrderStatusSnapshot].self, forKey: StorageKey.snapshots) ?? [:]
    }

    private func persist(_ snapshots: [String: OrderStatusSnapshot]) {
        do {
            try store.setCodable(snapshots, forKey: StorageKey.snapshots)
        } catch {
            Logger(category: "OrderNotification").warning("[OrderNotification] snapshot persist failed error=\(error.localizedDescription)")
        }
    }
}

@MainActor
final class InMemoryOrderStatusSnapshotStore: OrderStatusSnapshotStore {
    private var statuses: [String: String] = [:]

    func status(for orderCode: String) -> String? {
        statuses[orderCode]
    }

    func saveStatus(_ status: String, for orderCode: String) {
        statuses[orderCode] = status
    }

    func saveStatuses(_ statuses: [String: String]) {
        for (orderCode, status) in statuses {
            self.statuses[orderCode] = status
        }
    }

    func count() -> Int {
        statuses.count
    }
}

struct CommunityPostNotificationSnapshot: Codable, Equatable {
    let postId: String
    let commentCount: Int?
    let likeCount: Int?
    let updatedAt: Date?
}

@MainActor
protocol CommunityNotificationSnapshotStore {
    func snapshot(for postId: String) -> CommunityPostNotificationSnapshot?
    func saveSnapshot(_ snapshot: CommunityPostNotificationSnapshot)
    func count() -> Int
}

@MainActor
final class UserDefaultsCommunityNotificationSnapshotStore: CommunityNotificationSnapshotStore {
    private enum StorageKey {
        static let snapshots = "notification.communityPostSnapshots"
    }

    private let store: any UserDefaultsStoring

    init(store: any UserDefaultsStoring) {
        self.store = store
    }

    func snapshot(for postId: String) -> CommunityPostNotificationSnapshot? {
        snapshots()[postId]
    }

    func saveSnapshot(_ snapshot: CommunityPostNotificationSnapshot) {
        var values = snapshots()
        values[snapshot.postId] = snapshot
        persist(values)
    }

    func count() -> Int {
        snapshots().count
    }

    private func snapshots() -> [String: CommunityPostNotificationSnapshot] {
        store.codableValue([String: CommunityPostNotificationSnapshot].self, forKey: StorageKey.snapshots) ?? [:]
    }

    private func persist(_ snapshots: [String: CommunityPostNotificationSnapshot]) {
        do {
            try store.setCodable(snapshots, forKey: StorageKey.snapshots)
        } catch {
            Logger(category: "CommunityNotification").warning("[CommunityNotification] snapshot persist failed error=\(error.localizedDescription)")
        }
    }
}

@MainActor
final class InMemoryCommunityNotificationSnapshotStore: CommunityNotificationSnapshotStore {
    private var values: [String: CommunityPostNotificationSnapshot] = [:]

    func snapshot(for postId: String) -> CommunityPostNotificationSnapshot? {
        values[postId]
    }

    func saveSnapshot(_ snapshot: CommunityPostNotificationSnapshot) {
        values[snapshot.postId] = snapshot
    }

    func count() -> Int {
        values.count
    }
}

@MainActor
final class NotificationDiagnosticsStore: ObservableObject {
    @Published private(set) var latestRemotePayload: [String: String]?
    @Published private(set) var lastAuthorizationStatus = "unknown"
    @Published private(set) var hasAPNsToken = false
    @Published private(set) var lastLocalNotificationID: String?
    @Published private(set) var lastServerPushStatus = "remote push not tested"
    @Published private(set) var lastServerPushErrorMessage: String?
    @Published private(set) var lastForegroundPresentationSource = "없음"
    @Published private(set) var lastForegroundPresentationResult = "없음"
    @Published private(set) var lastRemoteTapRoute = "없음"
    @Published private(set) var pendingNotificationRoute = "없음"

    func recordRemotePayload(_ payload: [String: String]) {
        latestRemotePayload = payload
    }

    func recordAuthorizationStatus(_ status: String) {
        lastAuthorizationStatus = status
    }

    func recordAPNsTokenRegistered() {
        hasAPNsToken = true
    }

    func recordLocalNotification(id: String) {
        lastLocalNotificationID = id
    }

    func recordServerPushStatus(_ status: String, errorMessage: String? = nil) {
        lastServerPushStatus = status
        lastServerPushErrorMessage = errorMessage
    }

    func recordForegroundPresentation(source: String, result: String) {
        lastForegroundPresentationSource = source
        lastForegroundPresentationResult = result
    }

    func recordRemoteTapRoute(_ route: String, pendingRoute: String?) {
        lastRemoteTapRoute = route
        pendingNotificationRoute = pendingRoute ?? "없음"
    }
}
