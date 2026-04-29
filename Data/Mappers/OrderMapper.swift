import Foundation

struct OrderMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let dateParser: DateParser
    private let currencyFormatter: CurrencyFormatter

    init(
        fileURLResolver: any AuthorizedFileURLResolving,
        dateParser: DateParser = DateParser(),
        currencyFormatter: CurrencyFormatter = CurrencyFormatter()
    ) {
        self.fileURLResolver = fileURLResolver
        self.dateParser = dateParser
        self.currencyFormatter = currencyFormatter
    }

    func mapCreatedOrder(_ dto: OrderCreateResponseDTO) -> CreatedOrder {
        CreatedOrder(
            id: dto.orderID,
            orderCode: dto.orderCode,
            totalPriceAmount: Decimal(dto.totalPrice),
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            paymentBridgePayload: makePaymentBridgePayload(dto)
        )
    }

    func mapOrderPage(_ dto: OrderListResponseDTO) -> CursorPage<OrderSummary> {
        CursorPage(
            items: dto.data.map(mapOrderSummary),
            nextCursor: nil
        )
    }

    func mapOrderDetail(
        _ dto: OrderWithStatusResponseDTO,
        paymentReceipt: PaymentResponseDTO?
    ) -> OrderDetail {
        let paidAt = paymentReceipt?.paidAt.flatMap(dateParser.parseISO8601)
            ?? dto.paidAt.flatMap(dateParser.parseISO8601)
        let items = dto.orderMenuList.map(mapOrderItemSummary)
        logOrderMapping(
            orderCode: dto.orderCode,
            orderStatus: dto.currentOrderStatus,
            paymentStatus: paymentReceipt?.status,
            paidAt: paidAt,
            receiptURL: paymentReceipt?.receiptURL
        )

        return OrderDetail(
            orderID: dto.orderID,
            orderCode: dto.orderCode,
            storeID: dto.store.id,
            storeName: dto.store.name,
            storeCategory: dto.store.category,
            storeCloseTime: dto.store.close,
            storeImagePath: dto.store.storeImageURLs.first.map(resolveAuthorizedPath),
            status: OrderStatus(serverValue: dto.currentOrderStatus),
            createdAt: dateParser.parseISO8601(dto.createdAt) ?? .distantPast,
            updatedAt: dateParser.parseISO8601(dto.updatedAt) ?? .distantPast,
            paidAt: paidAt,
            pickupTime: dto.orderStatusTimeline.first(where: { OrderStatus(serverValue: $0.status) == .ready })?.changedAt.flatMap(dateParser.parseISO8601),
            totalAmount: dto.totalPrice,
            items: items,
            timeline: dto.orderStatusTimeline.map(mapTimelineEntry),
            paymentSummary: mapPaymentSummary(paymentReceipt, fallbackPaidAt: paidAt),
            userMemo: nil,
            reviewID: dto.review?.id,
            reviewRating: dto.review?.rating
        )
    }

    func mapValidatedPaymentReceipt(_ dto: ReceiptOrderResponseDTO) -> ValidatedPaymentReceipt {
        ValidatedPaymentReceipt(
            paymentID: dto.paymentID,
            orderID: dto.orderItem?.orderID,
            orderCode: dto.orderItem?.orderCode,
            totalPriceAmount: dto.orderItem?.totalPrice,
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601)
        )
    }

    func mapPaymentReceipt(_ dto: PaymentResponseDTO) -> PaymentReceipt {
        PaymentReceipt(
            impUID: dto.impUID,
            merchantUID: dto.merchantUID,
            amount: dto.amount,
            currency: dto.currency,
            status: dto.status,
            methodText: dto.payMethod,
            paidAt: dto.paidAt.flatMap(dateParser.parseISO8601),
            receiptURL: dto.receiptURL.flatMap(URL.init(string:))
        )
    }

    func statusTitle(for status: OrderStatus) -> String {
        status.displayTitle
    }

    func currencyText(for amount: Decimal) -> String {
        currencyFormatter.string(from: amount)
    }

    func createdOrderTimestampText(from date: Date) -> String {
        dateParser.string(from: date, format: "M월 d일 a h:mm")
    }

    private func mapOrderSummary(_ dto: OrderWithStatusResponseDTO) -> OrderSummary {
        let paidAt = dto.paidAt.flatMap(dateParser.parseISO8601)
        logOrderMapping(
            orderCode: dto.orderCode,
            orderStatus: dto.currentOrderStatus,
            paymentStatus: nil,
            paidAt: paidAt,
            receiptURL: nil
        )

        return OrderSummary(
            id: dto.orderID,
            orderCode: dto.orderCode,
            storeID: dto.store.id,
            storeName: dto.store.name,
            storeImagePath: dto.store.storeImageURLs.first.map(resolveAuthorizedPath),
            status: OrderStatus(serverValue: dto.currentOrderStatus),
            createdAt: dateParser.parseISO8601(dto.createdAt) ?? .distantPast,
            paidAt: paidAt,
            totalAmount: dto.totalPrice,
            itemSummaries: dto.orderMenuList.map(mapOrderItemSummary),
            pickupTime: dto.orderStatusTimeline.first(where: { OrderStatus(serverValue: $0.status) == .ready })?.changedAt.flatMap(dateParser.parseISO8601),
            reviewID: dto.review?.id,
            reviewRating: dto.review?.rating
        )
    }

    private func mapOrderItemSummary(_ dto: OrderMenuQuantityResponseDTO) -> OrderItemSummary {
        OrderItemSummary(
            id: dto.menu.id,
            menuName: dto.menu.name ?? "메뉴 정보 준비 중",
            quantity: dto.quantity,
            imagePath: dto.menu.menuImageURL.map(resolveAuthorizedPath),
            unitPriceAmount: dto.menu.price
        )
    }

    private func mapTimelineEntry(_ dto: OrderStatusTimelineResponseDTO) -> OrderStatusTimelineEntry {
        OrderStatusTimelineEntry(
            id: "\(dto.status)-\(dto.changedAt ?? "pending")",
            status: OrderStatus(serverValue: dto.status),
            completed: dto.completed,
            changedAt: dto.changedAt.flatMap(dateParser.parseISO8601)
        )
    }

    private func mapPaymentSummary(
        _ dto: PaymentResponseDTO?,
        fallbackPaidAt: Date?
    ) -> OrderPaymentSummary? {
        guard dto != nil || fallbackPaidAt != nil else {
            return nil
        }

        return OrderPaymentSummary(
            statusText: dto?.status,
            methodText: dto?.payMethod,
            paidAt: dto?.paidAt.flatMap(dateParser.parseISO8601) ?? fallbackPaidAt,
            receiptURL: dto?.receiptURL.flatMap(URL.init(string:))
        )
    }

    private func logOrderMapping(
        orderCode: String,
        orderStatus: String,
        paymentStatus: String?,
        paidAt: Date?,
        receiptURL: String?
    ) {
        Logger.shared.debug(
            "[OrderMapping] orderCode=\(orderCode) orderStatus=\(orderStatus) paymentStatus=\(paymentStatus ?? "nil") paidAtExists=\(paidAt != nil) receiptExists=\(receiptURL != nil)"
        )
    }

    private func makePaymentBridgePayload(_ dto: OrderCreateResponseDTO) -> CheckoutPaymentBridgePayload? {
        let paymentURL = dto.paymentURL.flatMap(URL.init(string:))
        let redirectURL = dto.redirectURL.flatMap(URL.init(string:))

        guard paymentURL != nil || redirectURL != nil || dto.paymentToken != nil else {
            return nil
        }

        return CheckoutPaymentBridgePayload(
            paymentURL: paymentURL,
            redirectURL: redirectURL,
            paymentToken: dto.paymentToken
        )
    }

    private func resolveAuthorizedPath(_ path: String) -> String {
        (try? fileURLResolver.resolveOptionalURL(from: path))?.absoluteString ?? path
    }
}
