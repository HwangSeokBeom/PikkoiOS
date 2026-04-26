import Foundation

struct OrderMapper: Sendable {
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
}
