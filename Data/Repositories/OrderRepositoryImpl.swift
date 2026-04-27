import Foundation

struct OrderRepositoryImpl: OrderRepository {
    private let remoteDataSource: any OrderRemoteDataSourceProtocol
    private let checkoutMapper: CheckoutMapper
    private let mapper: OrderMapper
    private let localSnapshotStore: OrderLocalSnapshotStore

    init(
        remoteDataSource: any OrderRemoteDataSourceProtocol,
        checkoutMapper: CheckoutMapper,
        mapper: OrderMapper,
        localSnapshotStore: OrderLocalSnapshotStore = .shared
    ) {
        self.remoteDataSource = remoteDataSource
        self.checkoutMapper = checkoutMapper
        self.mapper = mapper
        self.localSnapshotStore = localSnapshotStore
    }

    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary> {
        do {
            let response = try await remoteDataSource.fetchOrders(cursor: cursor, filter: filter)
            let remotePage = mapper.mapOrderPage(response)
            guard cursor == nil else {
                return remotePage
            }
            let snapshots = await localSnapshotStore.summaries()
            return CursorPage(
                items: merge(remoteOrders: remotePage.items, localOrders: snapshots),
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
            return CursorPage(items: snapshots, nextCursor: nil)
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

        let paymentReceipt = try? await remoteDataSource.fetchPaymentReceipt(orderCode: matchedOrder.orderCode)
        return mapper.mapOrderDetail(matchedOrder, paymentReceipt: paymentReceipt)
    }

    func cancelOrder(orderCode: String) async throws -> OrderDetail {
        let isKnownRemoteOrder: Bool
        do {
            let response = try await remoteDataSource.fetchOrders(cursor: nil, filter: nil)
            isKnownRemoteOrder = response.data.contains { $0.orderCode == orderCode || $0.orderID == orderCode }
        } catch {
            if (error as? NetworkError)?.isAuthenticationFailure == true {
                throw error
            }
            isKnownRemoteOrder = false
        }

        if let localDetail = await localSnapshotStore.detail(matching: orderCode),
           !isKnownRemoteOrder,
           localDetail.status.isCancellable,
           localDetail.paidAt == nil,
           localDetail.paymentSummary?.paidAt == nil {
            let detail = makeCancelledDetail(from: localDetail)
            await localSnapshotStore.markCancelled(orderCode: orderCode, updatedAt: detail.updatedAt)
            postStatusChange(for: detail)
            return detail
        }

        try await remoteDataSource.updateOrderStatus(orderCode: orderCode, nextStatus: "CANCELLED")
        await localSnapshotStore.markCancelled(orderCode: orderCode, updatedAt: Date())

        let detail = makeCancelledDetail(from: try await fetchOrderDetail(orderID: orderCode))
        postStatusChange(for: detail)
        return detail
    }

    private func postStatusChange(for detail: OrderDetail) {
        NotificationCenter.default.post(
            name: .pikkoOrderStatusDidChange,
            object: nil,
            userInfo: [
                OrderStatusChangeNotificationUserInfoKey.event: OrderStatusChangeNotification(
                    orderID: detail.orderID,
                    orderCode: detail.orderCode,
                    status: detail.status
                )
            ]
        )
    }

    func validatePayment(impUID: String) async throws -> ValidatedPaymentReceipt {
        let response = try await remoteDataSource.validatePayment(impUID: impUID)
        return mapper.mapValidatedPaymentReceipt(response)
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
        return missingLocalOrders + remoteOrders
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
                totalAmount: $0.totalAmount,
                itemSummaries: $0.items,
                pickupTime: $0.pickupTime
            )
        }
    }

    func detail(matching orderIDOrCode: String) -> OrderDetail? {
        storedDetails.first {
            $0.orderID == orderIDOrCode || $0.orderCode == orderIDOrCode
        }
    }

    func markCancelled(orderCode: String, updatedAt: Date) {
        guard let index = storedDetails.firstIndex(where: { $0.orderCode == orderCode }) else {
            return
        }

        let existing = storedDetails[index]
        var timeline = existing.timeline
        if !timeline.contains(where: { $0.status == .cancelled }) {
            timeline.append(
                OrderStatusTimelineEntry(
                    id: "CANCELLED-\(orderCode)",
                    status: .cancelled,
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
            status: .cancelled,
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
        switch self {
        case .pending:
            return "PENDING_APPROVAL"
        case .accepted:
            return "APPROVED"
        case .preparing:
            return "IN_PROGRESS"
        case .ready:
            return "READY_FOR_PICKUP"
        case .completed:
            return "PICKED_UP"
        case .cancelled:
            return "CANCELLED"
        case .failed:
            return "FAILED"
        case .unknown(let value):
            return value
        }
    }
}
