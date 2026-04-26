import Foundation

protocol OrderRepository: Sendable {
    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary>
    func fetchOrderDetail(orderID: String) async throws -> OrderDetail
    func validatePayment(impUID: String) async throws -> ValidatedPaymentReceipt
    func validatePrice(_ request: CheckoutPriceValidationRequest) async throws -> CheckoutPriceValidationResult
    func createOrder(_ submission: CheckoutOrderSubmission) async throws -> CreatedOrder
}
