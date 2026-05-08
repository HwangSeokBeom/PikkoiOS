import Foundation

@MainActor
protocol OrderLiveActivityManaging: AnyObject {
    func start(order: OrderSummary)
    func update(order: OrderSummary)
    func sync(orders: [OrderSummary], source: String)
    func end(order: OrderSummary, reason: OrderLiveActivityEndReason)
    func endAll()
    func restoreExistingActivitiesIfNeeded()
}

enum OrderLiveActivityEndReason: String, Sendable {
    case pickedUp
    case cancelled
    case manual
}

@MainActor
final class NoopOrderLiveActivityManager: OrderLiveActivityManaging {
    static let shared = NoopOrderLiveActivityManager()

    func start(order: OrderSummary) {}
    func update(order: OrderSummary) {}
    func sync(orders: [OrderSummary], source: String) {}
    func end(order: OrderSummary, reason: OrderLiveActivityEndReason) {}
    func endAll() {}
    func restoreExistingActivitiesIfNeeded() {}
}

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class OrderLiveActivityManager: OrderLiveActivityManaging {
    static let shared = OrderLiveActivityManager()

    private let logger = Logger(category: "OrderLiveActivity")
    private var lastSnapshotByOrderCode: [String: OrderLiveActivitySnapshot] = [:]
    private var didRestore = false

    func start(order: OrderSummary) {
        guard isSupported else {
            logStartSkipped(reason: "unsupported")
            return
        }
        let authorizationInfo = ActivityAuthorizationInfo()
        logger.debug("[OrderLiveActivity] availability osSupported=true activityEnabled=\(authorizationInfo.areActivitiesEnabled)")
        guard authorizationInfo.areActivitiesEnabled else {
            logStartSkipped(reason: "disabled")
            return
        }
        guard let snapshot = OrderLiveActivitySnapshot(order: order) else {
            logStartSkipped(reason: "missingOrderCode")
            return
        }
        guard !snapshot.status.isTerminal else {
            logger.debug("[OrderLiveActivity] skipped reason=alreadyCompleted orderId=\(snapshot.orderId)")
            return
        }
        guard !hasActiveActivity(orderCode: snapshot.orderCode) else {
            logStartSkipped(reason: "alreadyExists")
            return
        }

        logger.debug("[OrderLiveActivity] start requested orderId=\(snapshot.orderId) status=\(snapshot.status.apiValue)")
        logger.debug("[OrderLiveActivity] deeplink target=orderDetail orderId=\(snapshot.orderId)")
        do {
            let attributes = OrderLiveActivityAttributes(
                orderId: snapshot.orderId,
                orderCode: snapshot.orderCode,
                storeName: snapshot.storeName,
                createdAt: snapshot.createdAt,
                estimatedReadyAt: snapshot.estimatedReadyAt
            )
            let content = ActivityContent(
                state: snapshot.activityContentState,
                staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: snapshot.updatedAt)
            )
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            lastSnapshotByOrderCode[snapshot.orderCode] = snapshot
            logger.info("[OrderLiveActivity] started orderId=\(snapshot.orderId) activityId=\(activity.id)")
        } catch {
            logger.warning("[OrderLiveActivity] start skipped reason=requestFailed orderId=\(snapshot.orderId) message=\(error.localizedDescription)")
        }
    }

    func update(order: OrderSummary) {
        guard isSupported else {
            logger.debug("[OrderLiveActivity] update skipped reason=unsupported")
            return
        }
        guard let snapshot = OrderLiveActivitySnapshot(order: order) else {
            logger.debug("[OrderLiveActivity] update skipped reason=missingOrderCode")
            return
        }
        if snapshot.status.isTerminal {
            end(order: order, reason: endReason(for: snapshot.status))
            return
        }
        guard hasActiveActivity(orderCode: snapshot.orderCode) else {
            logger.debug("[OrderLiveActivity] update skipped reason=noActiveActivity orderId=\(snapshot.orderId)")
            return
        }
        let oldSnapshot = lastSnapshotByOrderCode[snapshot.orderCode]
        guard oldSnapshot != snapshot else {
            logger.debug("[OrderLiveActivity] update skipped reason=sameState orderId=\(snapshot.orderId)")
            return
        }

        logger.debug("[OrderLiveActivity] update orderId=\(snapshot.orderId) status=\(snapshot.status.apiValue) progress=\(snapshot.progressStep)/\(snapshot.totalSteps)")
        Task { [snapshot] in
            let didUpdate = await Self.updateActivityKit(snapshot: snapshot)
            await MainActor.run {
                self.handleUpdateResult(didUpdate, snapshot: snapshot)
            }
        }
    }

    func sync(orders: [OrderSummary], source: String) {
        guard isSupported else { return }
        let activeOrders = orders.filter { !$0.status.isTerminal }
        logger.debug("[OrderLiveActivity] sync activeOrderCount=\(activeOrders.count)")
        guard !activeOrders.isEmpty else {
            logger.debug("[OrderLiveActivity] skipped reason=noActiveOrders")
            for order in orders where order.status.isTerminal {
                end(order: order, reason: endReason(for: order.status))
            }
            logger.debug("[OrderRefresh] liveActivity sync count=0")
            return
        }
        for order in activeOrders {
            if hasActiveActivity(orderCode: order.orderCode) {
                update(order: order)
            } else {
                start(order: order)
            }
        }
        for order in orders where order.status.isTerminal {
            end(order: order, reason: endReason(for: order.status))
        }
        logger.debug("[OrderRefresh] liveActivity sync count=\(activeOrders.count)")
    }

    func end(order: OrderSummary, reason: OrderLiveActivityEndReason) {
        guard isSupported else { return }
        guard let snapshot = OrderLiveActivitySnapshot(order: order),
              hasActiveActivity(orderCode: snapshot.orderCode) else {
            return
        }
        logger.debug("[OrderLiveActivity] end requested orderId=\(snapshot.orderId) reason=terminalStatus")
        Task { [snapshot, reason] in
            let didEnd = await Self.endActivityKit(snapshot: snapshot, reason: reason)
            await MainActor.run {
                self.handleEndResult(didEnd, snapshot: snapshot)
            }
        }
    }

    func endAll() {
        guard isSupported else { return }
        let orderCodes = Activity<OrderLiveActivityAttributes>.activities.map(\.attributes.orderCode)
        for orderCode in orderCodes {
            logger.debug("[OrderLiveActivity] end requested orderCode=\(orderCode) reason=manual")
        }
        Task { [orderCodes] in
            let endedOrderCodes = await Self.endActivityKit(orderCodes: orderCodes)
            await MainActor.run {
                self.handleEndAllResult(endedOrderCodes: endedOrderCodes)
            }
        }
        lastSnapshotByOrderCode.removeAll()
    }

    func restoreExistingActivitiesIfNeeded() {
        guard !didRestore else { return }
        didRestore = true
        guard isSupported else {
            logger.debug("[OrderLiveActivity] availability osSupported=false activityEnabled=false")
            return
        }
        let activities = Activity<OrderLiveActivityAttributes>.activities
        logger.debug("[OrderLiveActivity] restore existing count=\(activities.count)")
        for activity in activities {
            let attributes = activity.attributes
            let state = activity.content.state
            lastSnapshotByOrderCode[attributes.orderCode] = OrderLiveActivitySnapshot(
                orderId: attributes.orderId,
                orderCode: attributes.orderCode,
                storeName: attributes.storeName,
                createdAt: attributes.createdAt,
                estimatedReadyAt: attributes.estimatedReadyAt,
                status: OrderStatus(serverValue: state.status),
                progressStep: state.progressStep,
                totalSteps: state.totalSteps,
                canCancel: state.canCancel,
                pickupMessage: state.displayMessage,
                updatedAt: state.updatedAt,
                deepLinkURL: state.deepLinkURL
            )
        }
    }

    private var isSupported: Bool {
        if #available(iOS 16.1, *) {
            return true
        }
        return false
    }

    private func activity(orderCode: String) -> Activity<OrderLiveActivityAttributes>? {
        Activity<OrderLiveActivityAttributes>.activities.first { $0.attributes.orderCode == orderCode }
    }

    private func hasActiveActivity(orderCode: String) -> Bool {
        activity(orderCode: orderCode) != nil
    }

    private func handleUpdateResult(_ didUpdate: Bool, snapshot: OrderLiveActivitySnapshot) {
        guard didUpdate else {
            logger.debug("[OrderLiveActivity] update skipped reason=noActiveActivity orderId=\(snapshot.orderId)")
            return
        }
        lastSnapshotByOrderCode[snapshot.orderCode] = snapshot
        if snapshot.status == .completed {
            Task { [snapshot] in
                let didEnd = await Self.endActivityKit(snapshot: snapshot, reason: .pickedUp)
                await MainActor.run {
                    self.handleEndResult(didEnd, snapshot: snapshot)
                }
            }
        }
    }

    private func handleEndResult(_ didEnd: Bool, snapshot: OrderLiveActivitySnapshot) {
        guard didEnd else { return }
        lastSnapshotByOrderCode[snapshot.orderCode] = nil
        logger.info("[OrderLiveActivity] ended orderId=\(snapshot.orderId)")
    }

    private func handleEndAllResult(endedOrderCodes: [String]) {
        for orderCode in endedOrderCodes {
            lastSnapshotByOrderCode[orderCode] = nil
        }
    }

    private func endReason(for status: OrderStatus) -> OrderLiveActivityEndReason {
        switch status {
        case .completed:
            return .pickedUp
        case .cancelled, .rejected, .failed:
            return .cancelled
        case .pending, .accepted, .preparing, .ready, .unknown:
            return .manual
        }
    }

    nonisolated private static func updateActivityKit(snapshot: OrderLiveActivitySnapshot) async -> Bool {
        guard let activity = Activity<OrderLiveActivityAttributes>.activities.first(where: { $0.attributes.orderCode == snapshot.orderCode }) else {
            return false
        }
        await activity.update(
            ActivityContent(
                state: snapshot.activityContentState,
                staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: snapshot.updatedAt)
            )
        )
        return true
    }

    nonisolated private static func endActivityKit(snapshot: OrderLiveActivitySnapshot, reason: OrderLiveActivityEndReason) async -> Bool {
        guard let activity = Activity<OrderLiveActivityAttributes>.activities.first(where: { $0.attributes.orderCode == snapshot.orderCode }) else {
            return false
        }
        await activity.end(
            ActivityContent(state: snapshot.activityContentState, staleDate: nil),
            dismissalPolicy: reason == .manual ? .immediate : .after(Date().addingTimeInterval(60))
        )
        return true
    }

    nonisolated private static func endActivityKit(orderCodes: [String]) async -> [String] {
        var endedOrderCodes: [String] = []
        for orderCode in orderCodes {
            guard let activity = Activity<OrderLiveActivityAttributes>.activities.first(where: { $0.attributes.orderCode == orderCode }) else {
                continue
            }
            await activity.end(nil, dismissalPolicy: .immediate)
            endedOrderCodes.append(orderCode)
        }
        return endedOrderCodes
    }

    private func logStartSkipped(reason: String) {
        logger.debug("[OrderLiveActivity] start skipped reason=\(reason)")
    }
}
#else
typealias OrderLiveActivityManager = NoopOrderLiveActivityManager
#endif
