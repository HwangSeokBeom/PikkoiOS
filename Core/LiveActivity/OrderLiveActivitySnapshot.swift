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
        self.status = order.status
        self.progressStep = Self.progressStep(for: order.status)
        self.totalSteps = 5
        self.canCancel = order.canCancel
        self.pickupMessage = Self.pickupMessage(for: order.status, pickupTime: order.pickupTime)
        self.updatedAt = updatedAt
        self.deepLinkURL = deepLinkURL ?? URL(string: "pikko://orders/\(normalizedOrderCode)")
    }

    static func progressStep(for status: OrderStatus) -> Int {
        switch status {
        case .pending:
            return 1
        case .accepted:
            return 2
        case .preparing:
            return 3
        case .ready:
            return 4
        case .completed:
            return 5
        case .cancelled, .rejected, .failed, .unknown:
            return 0
        }
    }

    static func pickupMessage(for status: OrderStatus, pickupTime: Date?) -> String {
        switch status {
        case .pending:
            return "매장 승인 대기 중"
        case .accepted:
            return "매장이 주문을 확인했어요"
        case .preparing:
            return "메뉴를 준비하고 있어요"
        case .ready:
            return "매장에서 픽업해 주세요"
        case .completed:
            return "픽업이 완료되었어요"
        case .cancelled:
            return "주문이 취소되었어요"
        case .rejected:
            return "주문이 거절되었어요"
        case .failed:
            return "주문 처리에 실패했어요"
        case .unknown:
            return pickupTime.map { "픽업 예상 \($0.formatted(date: .omitted, time: .shortened))" } ?? "주문 상태 확인 중"
        }
    }
}

#if canImport(ActivityKit)
extension OrderLiveActivitySnapshot {
    var activityContentState: OrderLiveActivityAttributes.ContentState {
        OrderLiveActivityAttributes.ContentState(
            status: status.apiValue,
            statusText: status.displayTitle,
            statusTitle: status.displayTitle,
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
