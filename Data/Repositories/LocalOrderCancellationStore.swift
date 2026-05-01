import Foundation

struct LocalOrderCancellationRecord: Equatable, Sendable {
    let orderCode: String
    let cancelledAt: Date
    let rawOrderStatusAtCancel: String
    let totalPrice: Decimal
    let storeName: String
    let reason: String?
}

actor LocalOrderCancellationStore {
    static let shared = LocalOrderCancellationStore(store: UserDefaultsStore())

    private let store: any UserDefaultsStoring

    init(store: any UserDefaultsStoring) {
        self.store = store
    }

    func record(for orderCode: String, userID: String) -> LocalOrderCancellationRecord? {
        records(for: userID).first { $0.orderCode == orderCode }
    }

    func save(order: OrderSummary, userID: String, reason: String? = nil, cancelledAt: Date = Date()) {
        let record = LocalOrderCancellationRecord(
            orderCode: order.orderCode,
            cancelledAt: cancelledAt,
            rawOrderStatusAtCancel: order.status.apiValue,
            totalPrice: order.totalAmount,
            storeName: order.storeName,
            reason: reason
        )
        upsert(record, userID: userID)
        Logger.shared.debug(
            "[LocalOrderCancel] save orderCode=\(order.orderCode) status=\(order.status.apiValue) paid=\(order.isPaymentCompleted)"
        )
    }

    func save(detail: OrderDetail, userID: String, reason: String? = nil, cancelledAt: Date = Date()) {
        let record = LocalOrderCancellationRecord(
            orderCode: detail.orderCode,
            cancelledAt: cancelledAt,
            rawOrderStatusAtCancel: detail.status.apiValue,
            totalPrice: detail.totalAmount,
            storeName: detail.storeName,
            reason: reason
        )
        upsert(record, userID: userID)
        Logger.shared.debug(
            "[LocalOrderCancel] save orderCode=\(detail.orderCode) status=\(detail.status.apiValue) paid=\(detail.paidAt != nil || detail.paymentSummary?.paidAt != nil)"
        )
    }

    func remove(orderCode: String, userID: String) {
        var nextRecords = records(for: userID)
        let previousCount = nextRecords.count
        nextRecords.removeAll { $0.orderCode == orderCode }
        guard nextRecords.count != previousCount else { return }
        persist(nextRecords, userID: userID)
    }

    func apply(to orders: [OrderSummary], userID: String) -> [OrderSummary] {
        orders.map { apply(to: $0, userID: userID) }
    }

    func apply(to order: OrderSummary, userID: String) -> OrderSummary {
        guard record(for: order.orderCode, userID: userID) != nil else {
            return order
        }

        if order.status == .cancelled {
            remove(orderCode: order.orderCode, userID: userID)
            return order
        }

        guard order.status == .pending else {
            remove(orderCode: order.orderCode, userID: userID)
            Logger.shared.debug(
                "[LocalOrderCancel] removedStaleCancellation orderCode=\(order.orderCode) serverStatus=\(order.status.apiValue)"
            )
            return order
        }

        Logger.shared.debug(
            "[LocalOrderCancel] applied orderCode=\(order.orderCode) hiddenFromActiveOrders=true"
        )
        return order.updatingStatus(.cancelled, paymentVerificationState: order.paymentVerificationState)
    }

    func apply(to detail: OrderDetail, userID: String) -> OrderDetail {
        guard record(for: detail.orderCode, userID: userID) != nil else {
            return detail
        }

        if detail.status == .cancelled {
            remove(orderCode: detail.orderCode, userID: userID)
            return detail
        }

        guard detail.status == .pending else {
            remove(orderCode: detail.orderCode, userID: userID)
            Logger.shared.debug(
                "[LocalOrderCancel] removedStaleCancellation orderCode=\(detail.orderCode) serverStatus=\(detail.status.apiValue)"
            )
            return detail
        }

        Logger.shared.debug(
            "[LocalOrderCancel] applied orderCode=\(detail.orderCode) hiddenFromActiveOrders=true"
        )
        return detail.updatingStatus(.cancelled, updatedAt: Date())
    }

    private func upsert(_ record: LocalOrderCancellationRecord, userID: String) {
        var nextRecords = records(for: userID)
        nextRecords.removeAll { $0.orderCode == record.orderCode }
        nextRecords.insert(record, at: 0)
        persist(nextRecords, userID: userID)
    }

    private func records(for userID: String) -> [LocalOrderCancellationRecord] {
        store
            .codableValue([StoredLocalOrderCancellationRecord].self, forKey: storageKey(userID: userID))?
            .map(\.record) ?? []
    }

    private func persist(_ records: [LocalOrderCancellationRecord], userID: String) {
        do {
            try store.setCodable(
                records.map(StoredLocalOrderCancellationRecord.init(record:)),
                forKey: storageKey(userID: userID)
            )
        } catch {
            Logger.shared.warning(
                "[LocalOrderCancel] persistFailed userID=\(userID) message=\(error.localizedDescription)"
            )
        }
    }

    private func storageKey(userID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalizedUserID = userID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { scalar in
                allowed.contains(scalar) ? Character(scalar) : "_"
            }
        let suffix = String(normalizedUserID).isEmpty ? "unknown" : String(normalizedUserID)
        return "cancelled_order_codes_\(suffix)"
    }
}

private struct StoredLocalOrderCancellationRecord: Codable {
    let orderCode: String
    let cancelledAt: Date
    let rawOrderStatusAtCancel: String
    let totalPrice: Decimal
    let storeName: String
    let reason: String?

    init(record: LocalOrderCancellationRecord) {
        orderCode = record.orderCode
        cancelledAt = record.cancelledAt
        rawOrderStatusAtCancel = record.rawOrderStatusAtCancel
        totalPrice = record.totalPrice
        storeName = record.storeName
        reason = record.reason
    }

    var record: LocalOrderCancellationRecord {
        LocalOrderCancellationRecord(
            orderCode: orderCode,
            cancelledAt: cancelledAt,
            rawOrderStatusAtCancel: rawOrderStatusAtCancel,
            totalPrice: totalPrice,
            storeName: storeName,
            reason: reason
        )
    }
}

private extension OrderSummary {
    func updatingStatus(_ status: OrderStatus, paymentVerificationState: String?) -> OrderSummary {
        OrderSummary(
            id: id,
            orderCode: orderCode,
            storeID: storeID,
            storeName: storeName,
            storeImagePath: storeImagePath,
            status: status,
            createdAt: createdAt,
            paidAt: paidAt,
            totalAmount: totalAmount,
            itemSummaries: itemSummaries,
            pickupTime: pickupTime,
            reviewID: reviewID,
            reviewRating: reviewRating,
            paymentLookupKey: paymentLookupKey,
            paymentID: paymentID,
            merchantUID: merchantUID,
            impUID: impUID,
            paymentStatus: paymentStatus,
            paymentVerificationState: paymentVerificationState,
            receiptURL: receiptURL,
            receiptExists: receiptExists
        )
    }
}

private extension OrderDetail {
    func updatingStatus(_ status: OrderStatus, updatedAt: Date) -> OrderDetail {
        var nextTimeline = timeline
        if !nextTimeline.contains(where: { $0.status == status }) {
            nextTimeline.append(
                OrderStatusTimelineEntry(
                    id: "\(status.apiValue)-\(orderCode)",
                    status: status,
                    completed: true,
                    changedAt: updatedAt
                )
            )
        }

        return OrderDetail(
            orderID: orderID,
            orderCode: orderCode,
            storeID: storeID,
            storeName: storeName,
            storeCategory: storeCategory,
            storeCloseTime: storeCloseTime,
            storeImagePath: storeImagePath,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            paidAt: paidAt,
            pickupTime: pickupTime,
            totalAmount: totalAmount,
            items: items,
            timeline: nextTimeline,
            paymentSummary: paymentSummary,
            userMemo: userMemo,
            reviewID: reviewID,
            reviewRating: reviewRating
        )
    }
}
