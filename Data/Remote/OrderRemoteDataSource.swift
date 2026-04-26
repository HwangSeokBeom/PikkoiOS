import Foundation

protocol OrderRemoteDataSourceProtocol: Sendable {
    func fetchOrders(cursor: String?, filter: String?) async throws -> OrderListResponseDTO
    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentResponseDTO
    func validatePayment(impUID: String) async throws -> ReceiptOrderResponseDTO
    func validatePrice(_ request: CheckoutPriceValidationRequestDTO) async throws -> CheckoutPriceValidationResponseDTO
    func createOrder(_ request: OrderCreateRequestDTO) async throws -> OrderCreateResponseDTO
}

struct OrderRemoteDataSource: OrderRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchOrders(cursor: String?, filter: String?) async throws -> OrderListResponseDTO {
        // TODO: Confirm if the backend will expose cursor/filter parameters for /v1/orders.
        // Current Swagger describes GET /v1/orders without query parameters.
        let endpoint = Endpoint<OrderListResponseDTO>(
            path: "/v1/orders",
            method: .get,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentResponseDTO {
        let endpoint = Endpoint<PaymentResponseDTO>(
            path: "/v1/payments/\(orderCode)",
            method: .get,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func validatePayment(impUID: String) async throws -> ReceiptOrderResponseDTO {
        let endpoint = Endpoint<ReceiptOrderResponseDTO>(
            path: "/v1/payments/validation",
            method: .post,
            body: RequestBody.json(
                try NetworkCoding.makeJSONEncoder().encode(PaymentValidationRequestDTO(impUID: impUID))
            ),
            timeout: .paymentValidation,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func validatePrice(_ request: CheckoutPriceValidationRequestDTO) async throws -> CheckoutPriceValidationResponseDTO {
        // TODO: Confirm checkout validation endpoint path with backend Swagger.
        // The current Swagger only exposes POST /v1/orders and POST /v1/payments/validation,
        // so Checkout preflight validation falls back to a local request-shape check for now.
        let computedTotalPrice = request.orderMenuList.reduce(0) { $0 + $1.clientKnownLinePrice }
        var issues: [CheckoutPriceValidationIssueDTO] = []

        if request.orderMenuList.isEmpty {
            issues.append(
                CheckoutPriceValidationIssueDTO(
                    menuID: nil,
                    kind: "unknown",
                    message: "주문할 메뉴가 비어 있어요."
                )
            )
        }

        if computedTotalPrice != request.totalPrice {
            issues.append(
                CheckoutPriceValidationIssueDTO(
                    menuID: nil,
                    kind: "price_changed",
                    message: "장바구니 합계와 결제 예정 금액이 일치하지 않아요."
                )
            )
        }

        for item in request.orderMenuList where item.quantity <= 0 || item.clientKnownUnitPrice <= 0 || item.clientKnownLinePrice <= 0 {
            issues.append(
                CheckoutPriceValidationIssueDTO(
                    menuID: item.menuID,
                    kind: "unknown",
                    message: "수량 또는 가격 정보가 올바르지 않아요."
                )
            )
        }

        return CheckoutPriceValidationResponseDTO(
            validatedTotalPrice: computedTotalPrice,
            issues: issues,
            message: issues.isEmpty ? nil : "주문 정보를 다시 확인한 뒤 시도해 주세요."
        )
    }

    func createOrder(_ request: OrderCreateRequestDTO) async throws -> OrderCreateResponseDTO {
        let body = RequestBody.json(try JSONEncoder().encode(request))
        let endpoint = Endpoint<OrderCreateResponseDTO>(
            path: "/v1/orders",
            method: .post,
            body: body,
            timeout: .paymentValidation,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }
}
