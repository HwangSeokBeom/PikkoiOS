import Foundation

struct OrderLiveActivitySnapshot: Equatable, Sendable {
    let orderId: String
    let orderCode: String
    let storeName: String
    let createdAt: Date
    let estimatedReadyAt: Date?
    let status: OrderStatus
    let progressStep: Int
    let totalSteps: Int
    let canCancel: Bool
    let pickupMessage: String
    let updatedAt: Date
    let deepLinkURL: URL?

    init(
        orderId: String,
        orderCode: String,
        storeName: String,
        createdAt: Date,
        estimatedReadyAt: Date?,
        status: OrderStatus,
        progressStep: Int,
        totalSteps: Int,
        canCancel: Bool,
        pickupMessage: String,
        updatedAt: Date,
        deepLinkURL: URL?
    ) {
        self.orderId = orderId
        self.orderCode = orderCode
        self.storeName = storeName
        self.createdAt = createdAt
        self.estimatedReadyAt = estimatedReadyAt
        self.status = status
        self.progressStep = progressStep
        self.totalSteps = totalSteps
        self.canCancel = canCancel
        self.pickupMessage = pickupMessage
        self.updatedAt = updatedAt
        self.deepLinkURL = deepLinkURL
    }

    init?(
        order: OrderSummary,
        updatedAt: Date = Date(),
        deepLinkURL: URL? = nil
    ) {
        let normalizedOrderCode = order.orderCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOrderCode.isEmpty else {
            return nil
        }

        self.orderId = order.id
        self.orderCode = normalizedOrderCode
        self.storeName = order.storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Pikko" : order.storeName
        self.createdAt = order.createdAt
        self.estimatedReadyAt = order.pickupTime
        let statusDisplay = OrderLiveActivityStatusDisplay.map(status: order.status.apiValue)
        self.status = order.status
        self.progressStep = Int((statusDisplay.progress * 100).rounded())
        self.totalSteps = 100
        self.canCancel = order.canCancel
        self.pickupMessage = statusDisplay.message
        self.updatedAt = order.paidAt ?? updatedAt
        self.deepLinkURL = deepLinkURL ?? URL(string: "pikko://orders/\(normalizedOrderCode)")
    }

    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(progressStep) / Double(totalSteps)
    }

    static func progressStep(for status: OrderStatus) -> Int {
        Int((progress(for: status) * 100).rounded())
    }

    static func progress(for status: OrderStatus) -> Double {
        OrderLiveActivityStatusDisplay.map(status: status.apiValue).progress
    }

    static func pickupMessage(for status: OrderStatus, pickupTime: Date?) -> String {
        let display = OrderLiveActivityStatusDisplay.map(status: status.apiValue)
        if case .unknown = status {
            return pickupTime.map { "픽업 예상 \($0.formatted(date: .omitted, time: .shortened))" } ?? display.message
        }
        return display.message
    }
}

#if canImport(ActivityKit)
extension OrderLiveActivitySnapshot {
    var activityContentState: OrderLiveActivityAttributes.ContentState {
        OrderLiveActivityAttributes.ContentState(
            status: status.apiValue,
            statusText: status.liveActivityTitle,
            statusTitle: status.liveActivityTitle,
            progressStep: progressStep,
            totalSteps: totalSteps,
            displayMessage: pickupMessage,
            pickupMessage: pickupMessage,
            updatedAt: updatedAt,
            canCancel: canCancel,
            deepLinkURL: deepLinkURL
        )
    }
}
#endif

extension OrderStatus {
    var liveActivityTitle: String {
        OrderLiveActivityStatusDisplay.map(status: apiValue).badge
    }

    var isOrderLiveActivityActive: Bool {
        switch self {
        case .pending, .accepted, .preparing, .ready:
            return true
        case .completed, .cancelled, .rejected, .failed, .unknown:
            return false
        }
    }
}

extension OrderSummary {
    var isLiveActivityEligible: Bool {
        status.isOrderLiveActivityActive && isPaymentCompleted
    }
}
