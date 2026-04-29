import Foundation

protocol OrderRepository: Sendable {
    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary>
    func fetchOrderDetail(orderID: String) async throws -> OrderDetail
    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt
    func cancelOrder(orderCode: String) async throws -> OrderDetail
    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws
    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt
    func validatePrice(_ request: CheckoutPriceValidationRequest) async throws -> CheckoutPriceValidationResult
    func createOrder(_ submission: CheckoutOrderSubmission) async throws -> CreatedOrder
}
