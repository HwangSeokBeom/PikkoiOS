import Foundation

struct PaymentValidationRequestDTO: Encodable, Sendable {
    let impUID: String
    let orderCode: String?
    let merchantUID: String?
    let success: Bool?
    let errorMessage: String?

    init(request: PaymentValidationRequest) {
        self.impUID = request.impUID
        self.orderCode = request.orderCode
        self.merchantUID = request.merchantUID
        self.success = request.success
        self.errorMessage = request.errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case impUID = "imp_uid"
    }
}

struct PaymentResponseDTO: Decodable, Sendable {
    let impUID: String?
    let merchantUID: String
    let amount: Decimal
    let currency: String?
    let status: String
    let payMethod: String?
    let receiptURL: String?
    let paidAt: String?
    let startedAt: String?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case impUID = "imp_uid"
        case merchantUID = "merchant_uid"
        case amount
        case currency
        case status
        case payMethod = "pay_method"
        case receiptURL = "receipt_url"
        case paidAt
        case paidAtSnake = "paid_at"
        case startedAt
        case startedAtSnake = "started_at"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        impUID = try container.decodeIfPresent(String.self, forKey: .impUID)
        merchantUID = try container.decode(String.self, forKey: .merchantUID)
        amount = try container.decodeFlexibleDecimal(forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        status = try container.decode(String.self, forKey: .status)
        payMethod = try container.decodeIfPresent(String.self, forKey: .payMethod)
        receiptURL = try container.decodeIfPresent(String.self, forKey: .receiptURL)
        paidAt = try container.decodeIfPresent(String.self, forKey: .paidAt)
            ?? container.decodeIfPresent(String.self, forKey: .paidAtSnake)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
            ?? container.decodeIfPresent(String.self, forKey: .startedAtSnake)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

typealias PaymentReceiptResponseDTO = PaymentResponseDTO

struct ReceiptOrderResponseDTO: Decodable, Sendable {
    let paymentID: String?
    let orderItem: OrderResponseDTO?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case paymentID = "payment_id"
        case orderItem = "order_item"
        case createdAt
        case updatedAt
    }
}

struct OrderResponseDTO: Decodable, Sendable {
    let orderID: String
    let orderCode: String
    let totalPrice: Decimal
    let store: StoreSummaryDTOOrder
    let orderMenuList: [OrderMenuQuantityResponseDTO]
    let paidAt: String?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case orderCode = "order_code"
        case totalPrice = "total_price"
        case store
        case orderMenuList = "order_menu_list"
        case paidAt
        case paidAtSnake = "paid_at"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderID = try container.decode(String.self, forKey: .orderID)
        orderCode = try container.decode(String.self, forKey: .orderCode)
        totalPrice = try container.decodeFlexibleDecimal(forKey: .totalPrice)
        store = try container.decode(StoreSummaryDTOOrder.self, forKey: .store)
        orderMenuList = try container.decodeIfPresent([OrderMenuQuantityResponseDTO].self, forKey: .orderMenuList) ?? []
        paidAt = try container.decodeIfPresent(String.self, forKey: .paidAt)
            ?? container.decodeIfPresent(String.self, forKey: .paidAtSnake)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDecimal(forKey key: Key) throws -> Decimal {
        if let decimal = try decodeIfPresent(Decimal.self, forKey: key) {
            return decimal
        }
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return Decimal(intValue)
        }
        if let doubleValue = try decodeIfPresent(Double.self, forKey: key) {
            return Decimal(doubleValue)
        }
        if let stringValue = try decodeIfPresent(String.self, forKey: key),
           let decimal = Decimal(string: stringValue) {
            return decimal
        }

        throw DecodingError.keyNotFound(
            key,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Missing decimal-compatible value for \(key)")
        )
    }
}
