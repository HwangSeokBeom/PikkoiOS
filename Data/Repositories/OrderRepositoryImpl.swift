import Foundation

struct OrderRepositoryImpl: OrderRepository {
    private let remoteDataSource: any OrderRemoteDataSourceProtocol
    private let checkoutMapper: CheckoutMapper
    private let mapper: OrderMapper

    init(
        remoteDataSource: any OrderRemoteDataSourceProtocol,
        checkoutMapper: CheckoutMapper,
        mapper: OrderMapper
    ) {
        self.remoteDataSource = remoteDataSource
        self.checkoutMapper = checkoutMapper
        self.mapper = mapper
    }

    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary> {
        let response = try await remoteDataSource.fetchOrders(cursor: cursor, filter: filter)
        return mapper.mapOrderPage(response)
    }

    func fetchOrderDetail(orderID: String) async throws -> OrderDetail {
        // TODO: Confirm whether the backend will expose GET /v1/orders/{order_id}.
        // Current Swagger only documents GET /v1/orders, so detail is derived from the list response.
        let response = try await remoteDataSource.fetchOrders(cursor: nil, filter: nil)

        guard let matchedOrder = response.data.first(where: { $0.orderID == orderID || $0.orderCode == orderID }) else {
            throw NetworkError.notFound(message: "주문 정보를 찾을 수 없어요.")
        }

        let paymentReceipt = try? await remoteDataSource.fetchPaymentReceipt(orderCode: matchedOrder.orderCode)
        return mapper.mapOrderDetail(matchedOrder, paymentReceipt: paymentReceipt)
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
        return mapper.mapCreatedOrder(response)
    }
}
