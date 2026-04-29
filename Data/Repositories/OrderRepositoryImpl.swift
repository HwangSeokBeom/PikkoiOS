import Foundation

struct OrderRepositoryImpl: OrderRepository {
    private let remoteDataSource: any OrderRemoteDataSourceProtocol
    private let checkoutMapper: CheckoutMapper
    private let mapper: OrderMapper
    private let localSnapshotStore: OrderLocalSnapshotStore
    private let statusOverrideStore: OrderStatusOverrideStore

    init(
        remoteDataSource: any OrderRemoteDataSourceProtocol,
        checkoutMapper: CheckoutMapper,
        mapper: OrderMapper,
        localSnapshotStore: OrderLocalSnapshotStore = .shared,
        statusOverrideStore: OrderStatusOverrideStore = .shared
    ) {
        self.remoteDataSource = remoteDataSource
        self.checkoutMapper = checkoutMapper
        self.mapper = mapper
        self.localSnapshotStore = localSnapshotStore
        self.statusOverrideStore = statusOverrideStore
    }

    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary> {
        do {
            let response = try await remoteDataSource.fetchOrders(cursor: cursor, filter: filter)
            let remotePage = await mergeCachedState(into: mapper.mapOrderPage(response))
            guard cursor == nil else {
                return remotePage
            }
            for order in remotePage.items {
                await localSnapshotStore.record(summary: order)
            }
            let snapshots = await localSnapshotStore.summaries()
            let mergedSnapshots = await mergeCachedState(into: snapshots)
            return CursorPage(
                items: merge(remoteOrders: remotePage.items, localOrders: mergedSnapshots),
                nextCursor: remotePage.nextCursor
            )
        } catch {
            if (error as? NetworkError)?.isAuthenticationFailure == true {
                throw error
            }
            let snapshots = await localSnapshotStore.summaries()
            guard cursor == nil, !snapshots.isEmpty else {
                throw error
            }
            return CursorPage(items: await mergeCachedState(into: snapshots), nextCursor: nil)
        }
    }

    func fetchOrderDetail(orderID: String) async throws -> OrderDetail {
        // TODO: Confirm whether the backend will expose GET /v1/orders/{order_id}.
        // Current Swagger only documents GET /v1/orders, so detail is derived from the list response.
        let response: OrderListResponseDTO
        do {
            response = try await remoteDataSource.fetchOrders(cursor: nil, filter: nil)
        } catch {
            if let snapshotDetail = await localSnapshotStore.detail(matching: orderID) {
                return snapshotDetail
            }
            throw error
        }

        guard let matchedOrder = response.data.first(where: { $0.orderID == orderID || $0.orderCode == orderID }) else {
            if let snapshotDetail = await localSnapshotStore.detail(matching: orderID) {
                return snapshotDetail
            }
            throw NetworkError.notFound(message: "주문 정보를 찾을 수 없어요.")
        }

        let shouldFetchReceipt = matchedOrder.receiptExists == true
            || matchedOrder.receiptURL != nil
            || matchedOrder.paidAt != nil
            || matchedOrder.paymentStatus?.lowercased() == "paid"
        Logger.shared.debug(
            "[PaymentReceipt] autoFetch decision orderCode=\(matchedOrder.orderCode) paidAtExists=\(matchedOrder.paidAt != nil) receiptExists=\(matchedOrder.receiptExists == true) cacheState=none shouldFetch=\(shouldFetchReceipt) reason=\(shouldFetchReceipt ? "paymentEvidencePresent" : "noPaymentEvidence")"
        )
        let paymentReceipt = shouldFetchReceipt
            ? try? await remoteDataSource.fetchPaymentReceipt(orderCode: matchedOrder.orderCode)
            : nil
        let mappedDetail = mapper.mapOrderDetail(matchedOrder, paymentReceipt: paymentReceipt)
        return await mergeCachedState(into: mappedDetail)
    }

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt {
        do {
            let response = try await remoteDataSource.fetchPaymentReceipt(orderCode: orderCode)
            let receipt = mapper.mapPaymentReceipt(response)
            await PaymentReceiptCache.shared.markVerified(orderCode: orderCode, receipt: receipt)
            return receipt
        } catch {
            if case .notFound = error as? NetworkError {
                await PaymentReceiptCache.shared.markUnavailable(orderCode: orderCode)
            }
            throw error
        }
    }

    func cancelOrder(orderCode: String) async throws -> OrderDetail {
        Logger.shared.debug("[OrderCancel] request orderCode=\(orderCode)")
        let previousDetail = try? await fetchOrderDetail(orderID: orderCode)
        do {
            try await remoteDataSource.updateOrderStatus(orderCode: orderCode, nextStatus: OrderStatus.cancelled.apiValue)
            let updatedAt = Date()
            await statusOverrideStore.record(orderCode: orderCode, status: .cancelled, updatedAt: updatedAt)
            await localSnapshotStore.markStatus(orderCode: orderCode, status: .cancelled, updatedAt: updatedAt)
            if let previousDetail {
                await localSnapshotStore.record(detail: makeCancelledDetail(from: previousDetail))
            }
            Logger.shared.debug("[OrderCancel] success orderCode=\(orderCode)")
            postStatusChange(orderID: previousDetail?.orderID, orderCode: orderCode, status: .cancelled)
            return previousDetail.map(makeCancelledDetail(from:)) ?? makeFallbackCancelledDetail(orderCode: orderCode)
        } catch {
            Logger.shared.warning("[OrderCancel] failed orderCode=\(orderCode) message=\(error.localizedDescription)")
            throw error
        }
    }

    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws {
        try await remoteDataSource.updateOrderStatus(orderCode: orderCode, nextStatus: status.apiValue)
        let updatedAt = Date()
        await statusOverrideStore.record(orderCode: orderCode, status: status, updatedAt: updatedAt)
        await localSnapshotStore.markStatus(orderCode: orderCode, status: status, updatedAt: updatedAt)
        postStatusChange(orderID: nil, orderCode: orderCode, status: status)
    }

    private func postStatusChange(orderID: String?, orderCode: String, status: OrderStatus) {
        NotificationCenter.default.post(
            name: .pikkoOrderStatusDidChange,
            object: nil,
            userInfo: [
                OrderStatusChangeNotificationUserInfoKey.event: OrderStatusChangeNotification(
                    orderID: orderID,
                    orderCode: orderCode,
                    status: status
                )
            ]
        )
    }

    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt {
        let response = try await remoteDataSource.validatePayment(.init(request: request))
        let receipt = mapper.mapValidatedPaymentReceipt(response)
        if let orderCode = receipt.orderCode ?? request.orderCode {
            await PaymentReceiptCache.shared.markVerified(orderCode: orderCode)
            Logger.shared.debug("[PaymentValidation] cache verified orderCode=\(orderCode)")
        }
        return receipt
    }

    func validatePrice(_ request: CheckoutPriceValidationRequest) async throws -> CheckoutPriceValidationResult {
        let dto = checkoutMapper.mapValidationRequest(request)
        let response = try await remoteDataSource.validatePrice(dto)
        return checkoutMapper.mapValidationResponse(response)
    }

    func createOrder(_ submission: CheckoutOrderSubmission) async throws -> CreatedOrder {
        let response = try await remoteDataSource.createOrder(.init(submission: submission))
        let createdOrder = mapper.mapCreatedOrder(response)
        await localSnapshotStore.record(createdOrder: createdOrder, submission: submission)
        return createdOrder
    }

    private func merge(remoteOrders: [OrderSummary], localOrders: [OrderSummary]) -> [OrderSummary] {
        let remoteIDs = Set(remoteOrders.map(\.id))
        let remoteCodes = Set(remoteOrders.map(\.orderCode))
        let missingLocalOrders = localOrders.filter {
            !remoteIDs.contains($0.id) && !remoteCodes.contains($0.orderCode)
        }
        return (missingLocalOrders + remoteOrders).sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private func mergeCachedState(into page: CursorPage<OrderSummary>) async -> CursorPage<OrderSummary> {
        CursorPage(
            items: await mergeCachedState(into: page.items),
            nextCursor: page.nextCursor
        )
    }

    private func mergeCachedState(into orders: [OrderSummary]) async -> [OrderSummary] {
        var mergedOrders: [OrderSummary] = []
        for order in orders {
            mergedOrders.append(await mergeCachedState(into: order))
        }
        return mergedOrders
    }

    private func mergeCachedState(into order: OrderSummary) async -> OrderSummary {
        let cacheState = await PaymentReceiptCache.shared.state(for: order.orderCode)
        let overrideStatus = await statusOverrideStore.statusIfPreferred(
            orderCode: order.orderCode,
            serverStatus: order.status
        )
        let finalStatus = overrideStatus ?? order.status
        let finalPaymentState = mergedPaymentVerificationState(
            order: order,
            cacheState: cacheState
        )
        Logger.shared.debug(
            "[OrderMapping] statusMerge orderCode=\(order.orderCode) dtoStatus=\(order.status.apiValue) cachedPaymentState=\(cacheState?.logValue ?? "none") localOverrideStatus=\(overrideStatus?.apiValue ?? "nil") finalStatus=\(finalStatus.apiValue) finalPaymentState=\(finalPaymentState ?? "unchecked")"
        )

        return OrderSummary(
            id: order.id,
            orderCode: order.orderCode,
            storeID: order.storeID,
            storeName: order.storeName,
            storeImagePath: order.storeImagePath,
            status: finalStatus,
            createdAt: order.createdAt,
            paidAt: order.paidAt,
            totalAmount: order.totalAmount,
            itemSummaries: order.itemSummaries,
            pickupTime: order.pickupTime,
            reviewID: order.reviewID,
            reviewRating: order.reviewRating,
            paymentLookupKey: order.paymentLookupKey,
            paymentID: order.paymentID,
            merchantUID: order.merchantUID,
            impUID: order.impUID,
            paymentStatus: order.paymentStatus,
            paymentVerificationState: finalPaymentState,
            receiptURL: order.receiptURL,
            receiptExists: order.receiptExists || cacheState?.isVerified == true
        )
    }

    private func mergeCachedState(into detail: OrderDetail) async -> OrderDetail {
        let overrideStatus = await statusOverrideStore.statusIfPreferred(
            orderCode: detail.orderCode,
            serverStatus: detail.status
        )
        let finalStatus = overrideStatus ?? detail.status
        guard finalStatus != detail.status else {
            return detail
        }

        return OrderDetail(
            orderID: detail.orderID,
            orderCode: detail.orderCode,
            storeID: detail.storeID,
            storeName: detail.storeName,
            storeCategory: detail.storeCategory,
            storeCloseTime: detail.storeCloseTime,
            storeImagePath: detail.storeImagePath,
            status: finalStatus,
            createdAt: detail.createdAt,
            updatedAt: detail.updatedAt,
            paidAt: detail.paidAt,
            pickupTime: detail.pickupTime,
            totalAmount: detail.totalAmount,
            items: detail.items,
            timeline: detail.timeline,
            paymentSummary: detail.paymentSummary,
            userMemo: detail.userMemo,
            reviewID: detail.reviewID,
            reviewRating: detail.reviewRating
        )
    }

    private func mergedPaymentVerificationState(
        order: OrderSummary,
        cacheState: PaymentReceiptCacheState?
    ) -> String? {
        let rawState = order.paymentVerificationState?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if rawState == "verified" {
            return "verified"
        }
        if order.paymentStatus?.lowercased() == "paid", order.paidAt != nil {
            return "verified"
        }
        if cacheState?.isVerified == true {
            return "verified"
        }
        return order.paymentVerificationState
    }

    private func makeCancelledDetail(from detail: OrderDetail) -> OrderDetail {
        guard detail.status != .cancelled else {
            return detail
        }

        let updatedAt = Date()
        var timeline = detail.timeline
        if !timeline.contains(where: { $0.status == .cancelled }) {
            timeline.append(
                OrderStatusTimelineEntry(
                    id: "CANCELLED-\(detail.orderCode)",
                    status: .cancelled,
                    completed: true,
                    changedAt: updatedAt
                )
            )
        }

        return OrderDetail(
            orderID: detail.orderID,
            orderCode: detail.orderCode,
            storeID: detail.storeID,
            storeName: detail.storeName,
            storeCategory: detail.storeCategory,
            storeCloseTime: detail.storeCloseTime,
            storeImagePath: detail.storeImagePath,
            status: .cancelled,
            createdAt: detail.createdAt,
            updatedAt: updatedAt,
            paidAt: detail.paidAt,
            pickupTime: detail.pickupTime,
            totalAmount: detail.totalAmount,
            items: detail.items,
            timeline: timeline,
            paymentSummary: detail.paymentSummary,
            userMemo: detail.userMemo,
            reviewID: detail.reviewID,
            reviewRating: detail.reviewRating
        )
    }

    private func makeFallbackCancelledDetail(orderCode: String) -> OrderDetail {
        let now = Date()
        return OrderDetail(
            orderID: orderCode,
            orderCode: orderCode,
            storeID: "",
            storeName: "주문",
            storeCategory: nil,
            storeCloseTime: nil,
            storeImagePath: nil,
            status: .cancelled,
            createdAt: now,
            updatedAt: now,
            paidAt: nil,
            pickupTime: nil,
            totalAmount: 0,
            items: [],
            timeline: [
                OrderStatusTimelineEntry(
                    id: "CANCELLED-\(orderCode)",
                    status: .cancelled,
                    completed: true,
                    changedAt: now
                )
            ],
            paymentSummary: nil,
            userMemo: nil,
            reviewID: nil,
            reviewRating: nil
        )
    }
}

private extension PaymentReceiptCacheState {
    var isVerified: Bool {
        if case .verified = self {
            return true
        }
        return false
    }
}

actor OrderLocalSnapshotStore {
    static let shared = OrderLocalSnapshotStore(store: UserDefaultsStore())

    private let store: any UserDefaultsStoring
    private let storageKey: String
    private var storedDetails: [OrderDetail] = []

    init(
        store: any UserDefaultsStoring,
        storageKey: String = "order.localSnapshots"
    ) {
        self.store = store
        self.storageKey = storageKey
        self.storedDetails = store
            .codableValue([StoredOrderDetailSnapshot].self, forKey: storageKey)?
            .map(\.orderDetail) ?? []
    }

    func record(createdOrder: CreatedOrder, submission: CheckoutOrderSubmission) async {
        let items = submission.items.map {
            OrderItemSummary(
                id: $0.menuID,
                menuName: $0.menuName,
                quantity: $0.quantity,
                imagePath: $0.imagePath,
                unitPriceAmount: $0.unitPriceAmount
            )
        }
        let timeline = [
            OrderStatusTimelineEntry(
                id: "PENDING_APPROVAL-\(createdOrder.orderCode)",
                status: .pending,
                completed: true,
                changedAt: createdOrder.createdAt
            )
        ]
        let detail = OrderDetail(
            orderID: createdOrder.id,
            orderCode: createdOrder.orderCode,
            storeID: submission.storeID,
            storeName: submission.storeName,
            storeCategory: nil,
            storeCloseTime: nil,
            storeImagePath: items.first?.imagePath,
            status: .pending,
            createdAt: createdOrder.createdAt,
            updatedAt: createdOrder.updatedAt,
            paidAt: nil,
            pickupTime: nil,
            totalAmount: createdOrder.totalPriceAmount,
            items: items,
            timeline: timeline,
            paymentSummary: nil,
            userMemo: submission.pickupMemo.isEmpty ? nil : submission.pickupMemo,
            reviewID: nil,
            reviewRating: nil
        )

        storedDetails.removeAll {
            $0.orderID == createdOrder.id || $0.orderCode == createdOrder.orderCode
        }
        storedDetails.insert(detail, at: 0)
        storedDetails = Array(storedDetails.prefix(10))
        persist()
    }

    func record(summary: OrderSummary) {
        let timeline = [
            OrderStatusTimelineEntry(
                id: "\(summary.status.apiValue)-\(summary.orderCode)",
                status: summary.status,
                completed: true,
                changedAt: summary.createdAt
            )
        ]
        let detail = OrderDetail(
            orderID: summary.id,
            orderCode: summary.orderCode,
            storeID: summary.storeID,
            storeName: summary.storeName,
            storeCategory: nil,
            storeCloseTime: nil,
            storeImagePath: summary.storeImagePath,
            status: summary.status,
            createdAt: summary.createdAt,
            updatedAt: Date(),
            paidAt: summary.paidAt,
            pickupTime: summary.pickupTime,
            totalAmount: summary.totalAmount,
            items: summary.itemSummaries,
            timeline: timeline,
            paymentSummary: OrderPaymentSummary(
                statusText: summary.paymentStatus,
                methodText: nil,
                paidAt: summary.paidAt,
                receiptURL: summary.receiptURL
            ),
            userMemo: nil,
            reviewID: summary.reviewID,
            reviewRating: summary.reviewRating
        )
        record(detail: detail)
    }

    func record(detail: OrderDetail) {
        storedDetails.removeAll {
            $0.orderID == detail.orderID || $0.orderCode == detail.orderCode
        }
        storedDetails.insert(detail, at: 0)
        storedDetails = Array(storedDetails.prefix(20))
        persist()
    }

    func summaries() -> [OrderSummary] {
        storedDetails.map {
            OrderSummary(
                id: $0.orderID,
                orderCode: $0.orderCode,
                storeID: $0.storeID,
                storeName: $0.storeName,
                storeImagePath: $0.storeImagePath,
                status: $0.status,
                createdAt: $0.createdAt,
                paidAt: $0.paidAt,
                totalAmount: $0.totalAmount,
                itemSummaries: $0.items,
                pickupTime: $0.pickupTime,
                reviewID: $0.reviewID,
                reviewRating: $0.reviewRating,
                receiptURL: $0.paymentSummary?.receiptURL,
                receiptExists: $0.paymentSummary?.receiptURL != nil
            )
        }
    }

    func detail(matching orderIDOrCode: String) -> OrderDetail? {
        storedDetails.first {
            $0.orderID == orderIDOrCode || $0.orderCode == orderIDOrCode
        }
    }

    func markCancelled(orderCode: String, updatedAt: Date) {
        markStatus(orderCode: orderCode, status: .cancelled, updatedAt: updatedAt)
    }

    func markStatus(orderCode: String, status: OrderStatus, updatedAt: Date) {
        guard let index = storedDetails.firstIndex(where: { $0.orderCode == orderCode }) else {
            return
        }

        let existing = storedDetails[index]
        var timeline = existing.timeline
        if !timeline.contains(where: { $0.status == status }) {
            timeline.append(
                OrderStatusTimelineEntry(
                    id: "\(status.apiValue)-\(orderCode)",
                    status: status,
                    completed: true,
                    changedAt: updatedAt
                )
            )
        }

        storedDetails[index] = OrderDetail(
            orderID: existing.orderID,
            orderCode: existing.orderCode,
            storeID: existing.storeID,
            storeName: existing.storeName,
            storeCategory: existing.storeCategory,
            storeCloseTime: existing.storeCloseTime,
            storeImagePath: existing.storeImagePath,
            status: status,
            createdAt: existing.createdAt,
            updatedAt: updatedAt,
            paidAt: existing.paidAt,
            pickupTime: existing.pickupTime,
            totalAmount: existing.totalAmount,
            items: existing.items,
            timeline: timeline,
            paymentSummary: existing.paymentSummary,
            userMemo: existing.userMemo,
            reviewID: existing.reviewID,
            reviewRating: existing.reviewRating
        )
        persist()
    }

    func clear() {
        storedDetails = []
        store.removeValue(forKey: storageKey)
    }

    private func persist() {
        do {
            try store.setCodable(
                storedDetails.map { StoredOrderDetailSnapshot(detail: $0) },
                forKey: storageKey
            )
        } catch {
            Logger.shared.warning("Failed to persist local order snapshots: \(error.localizedDescription)")
        }
    }
}

actor OrderStatusOverrideStore {
    static let shared = OrderStatusOverrideStore(store: UserDefaultsStore())

    private struct Entry: Sendable {
        let status: OrderStatus
        let updatedAt: Date
    }

    private let store: any UserDefaultsStoring
    private let storageKey: String
    private let ttl: TimeInterval
    private var entries: [String: Entry]

    init(
        store: any UserDefaultsStoring,
        storageKey: String = "order.statusOverrides",
        ttl: TimeInterval = 1_800
    ) {
        self.store = store
        self.storageKey = storageKey
        self.ttl = ttl
        self.entries = store
            .codableValue([StoredOrderStatusOverride].self, forKey: storageKey)?
            .reduce(into: [String: Entry]()) { partial, storedOverride in
                partial[storedOverride.orderCode] = Entry(
                    status: OrderStatus(serverValue: storedOverride.status),
                    updatedAt: storedOverride.updatedAt
                )
            } ?? [:]
    }

    func record(orderCode: String, status: OrderStatus, updatedAt: Date = Date()) {
        entries[orderCode] = Entry(status: status, updatedAt: updatedAt)
        persist()
    }

    func statusIfPreferred(orderCode: String, serverStatus: OrderStatus, now: Date = Date()) -> OrderStatus? {
        guard let entry = entries[orderCode] else { return nil }

        if now.timeIntervalSince(entry.updatedAt) > ttl {
            entries[orderCode] = nil
            persist()
            Logger.shared.debug("[OrderStatus] localOverrideExpired orderCode=\(orderCode)")
            return nil
        }

        if serverStatus == entry.status {
            entries[orderCode] = nil
            persist()
            return nil
        }

        if serverStatus.isSameOrLaterProgressStep(than: entry.status) {
            entries[orderCode] = nil
            persist()
            return nil
        }

        if entry.status.isLaterProgressStep(than: serverStatus) || entry.status == .cancelled {
            Logger.shared.debug(
                "[OrderStatus] serverRegressionIgnored orderCode=\(orderCode) serverStatus=\(serverStatus.apiValue) localStatus=\(entry.status.apiValue)"
            )
            return entry.status
        }

        return nil
    }

    func clear() {
        entries = [:]
        store.removeValue(forKey: storageKey)
    }

    private func persist() {
        do {
            try store.setCodable(
                entries.map { orderCode, entry in
                    StoredOrderStatusOverride(
                        orderCode: orderCode,
                        status: entry.status.apiValue,
                        updatedAt: entry.updatedAt
                    )
                },
                forKey: storageKey
            )
        } catch {
            Logger.shared.warning("Failed to persist order status overrides: \(error.localizedDescription)")
        }
    }
}

private struct StoredOrderStatusOverride: Codable {
    let orderCode: String
    let status: String
    let updatedAt: Date
}

private struct StoredOrderDetailSnapshot: Codable {
    let orderID: String
    let orderCode: String
    let storeID: String
    let storeName: String
    let storeCategory: String?
    let storeCloseTime: String?
    let storeImagePath: String?
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let paidAt: Date?
    let pickupTime: Date?
    let totalAmount: Decimal
    let items: [StoredOrderItemSnapshot]
    let timeline: [StoredOrderTimelineSnapshot]
    let paymentSummary: StoredOrderPaymentSnapshot?
    let userMemo: String?
    let reviewID: String?
    let reviewRating: Decimal?

    init(detail: OrderDetail) {
        orderID = detail.orderID
        orderCode = detail.orderCode
        storeID = detail.storeID
        storeName = detail.storeName
        storeCategory = detail.storeCategory
        storeCloseTime = detail.storeCloseTime
        storeImagePath = detail.storeImagePath
        status = detail.status.serverStorageValue
        createdAt = detail.createdAt
        updatedAt = detail.updatedAt
        paidAt = detail.paidAt
        pickupTime = detail.pickupTime
        totalAmount = detail.totalAmount
        items = detail.items.map { StoredOrderItemSnapshot(item: $0) }
        timeline = detail.timeline.map { StoredOrderTimelineSnapshot(entry: $0) }
        paymentSummary = detail.paymentSummary.map { StoredOrderPaymentSnapshot(paymentSummary: $0) }
        userMemo = detail.userMemo
        reviewID = detail.reviewID
        reviewRating = detail.reviewRating
    }

    var orderDetail: OrderDetail {
        OrderDetail(
            orderID: orderID,
            orderCode: orderCode,
            storeID: storeID,
            storeName: storeName,
            storeCategory: storeCategory,
            storeCloseTime: storeCloseTime,
            storeImagePath: storeImagePath,
            status: OrderStatus(serverValue: status),
            createdAt: createdAt,
            updatedAt: updatedAt,
            paidAt: paidAt,
            pickupTime: pickupTime,
            totalAmount: totalAmount,
            items: items.map(\.orderItemSummary),
            timeline: timeline.map(\.timelineEntry),
            paymentSummary: paymentSummary?.paymentSummary,
            userMemo: userMemo,
            reviewID: reviewID,
            reviewRating: reviewRating
        )
    }
}

private struct StoredOrderItemSnapshot: Codable {
    let id: String
    let menuName: String
    let quantity: Int
    let imagePath: String?
    let unitPriceAmount: Decimal?

    init(item: OrderItemSummary) {
        id = item.id
        menuName = item.menuName
        quantity = item.quantity
        imagePath = item.imagePath
        unitPriceAmount = item.unitPriceAmount
    }

    var orderItemSummary: OrderItemSummary {
        OrderItemSummary(
            id: id,
            menuName: menuName,
            quantity: quantity,
            imagePath: imagePath,
            unitPriceAmount: unitPriceAmount
        )
    }
}

private struct StoredOrderTimelineSnapshot: Codable {
    let id: String
    let status: String
    let completed: Bool
    let changedAt: Date?

    init(entry: OrderStatusTimelineEntry) {
        id = entry.id
        status = entry.status.serverStorageValue
        completed = entry.completed
        changedAt = entry.changedAt
    }

    var timelineEntry: OrderStatusTimelineEntry {
        OrderStatusTimelineEntry(
            id: id,
            status: OrderStatus(serverValue: status),
            completed: completed,
            changedAt: changedAt
        )
    }
}

private struct StoredOrderPaymentSnapshot: Codable {
    let statusText: String?
    let methodText: String?
    let paidAt: Date?
    let receiptURLString: String?

    init(paymentSummary: OrderPaymentSummary) {
        statusText = paymentSummary.statusText
        methodText = paymentSummary.methodText
        paidAt = paymentSummary.paidAt
        receiptURLString = paymentSummary.receiptURL?.absoluteString
    }

    var paymentSummary: OrderPaymentSummary {
        OrderPaymentSummary(
            statusText: statusText,
            methodText: methodText,
            paidAt: paidAt,
            receiptURL: receiptURLString.flatMap(URL.init(string:))
        )
    }
}

private extension OrderStatus {
    var serverStorageValue: String {
        apiValue
    }

    func isLaterProgressStep(than status: OrderStatus) -> Bool {
        guard let currentStepIndex = progressStepIndex,
              let otherStepIndex = status.progressStepIndex else {
            return false
        }
        return currentStepIndex > otherStepIndex
    }

    func isSameOrLaterProgressStep(than status: OrderStatus) -> Bool {
        guard let currentStepIndex = progressStepIndex,
              let otherStepIndex = status.progressStepIndex else {
            return false
        }
        return currentStepIndex >= otherStepIndex
    }
}
