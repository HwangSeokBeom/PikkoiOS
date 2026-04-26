import Foundation

struct OrderDetail: Equatable, Sendable {
    let orderID: String
    let orderCode: String
    let storeID: String
    let storeName: String
    let storeCategory: String?
    let storeCloseTime: String?
    let storeImagePath: String?
    let status: OrderStatus
    let createdAt: Date
    let updatedAt: Date
    let paidAt: Date?
    let pickupTime: Date?
    let totalAmount: Decimal
    let items: [OrderItemSummary]
    let timeline: [OrderStatusTimelineEntry]
    let paymentSummary: OrderPaymentSummary?
    let userMemo: String?
    let reviewID: String?
    let reviewRating: Decimal?

    init(
        orderID: String,
        orderCode: String,
        storeID: String,
        storeName: String,
        storeCategory: String?,
        storeCloseTime: String?,
        storeImagePath: String?,
        status: OrderStatus,
        createdAt: Date,
        updatedAt: Date,
        paidAt: Date?,
        pickupTime: Date?,
        totalAmount: Decimal,
        items: [OrderItemSummary],
        timeline: [OrderStatusTimelineEntry],
        paymentSummary: OrderPaymentSummary?,
        userMemo: String?,
        reviewID: String? = nil,
        reviewRating: Decimal?
    ) {
        self.orderID = orderID
        self.orderCode = orderCode
        self.storeID = storeID
        self.storeName = storeName
        self.storeCategory = storeCategory
        self.storeCloseTime = storeCloseTime
        self.storeImagePath = storeImagePath
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.paidAt = paidAt
        self.pickupTime = pickupTime
        self.totalAmount = totalAmount
        self.items = items
        self.timeline = timeline
        self.paymentSummary = paymentSummary
        self.userMemo = userMemo
        self.reviewID = reviewID
        self.reviewRating = reviewRating
    }
}
