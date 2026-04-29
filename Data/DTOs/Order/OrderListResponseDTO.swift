import Foundation

struct OrderListResponseDTO: Decodable, Sendable {
    let data: [OrderWithStatusResponseDTO]
}

struct OrderWithStatusResponseDTO: Decodable, Sendable {
    let orderID: String
    let orderCode: String
    let totalPrice: Decimal
    let paymentLookupKey: String?
    let paymentID: String?
    let merchantUID: String?
    let impUID: String?
    let paymentStatus: String?
    let paymentVerificationState: String?
    let receiptURL: String?
    let receiptExists: Bool?
    let review: OrderReviewReferenceDTO?
    let store: StoreSummaryDTOOrder
    let orderMenuList: [OrderMenuQuantityResponseDTO]
    let currentOrderStatus: String
    let orderStatusTimeline: [OrderStatusTimelineResponseDTO]
    let paidAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case orderCode = "order_code"
        case totalPrice = "total_price"
        case paymentLookupKey = "payment_lookup_key"
        case paymentLookupKeyCamel = "paymentLookupKey"
        case paymentID = "payment_id"
        case paymentIDCamel = "paymentId"
        case merchantUID = "merchant_uid"
        case merchantUIDCamel = "merchantUid"
        case impUID = "imp_uid"
        case impUIDCamel = "impUid"
        case paymentStatus = "payment_status"
        case paymentStatusCamel = "paymentStatus"
        case paymentVerificationState = "payment_verification_state"
        case paymentVerificationStateCamel = "paymentVerificationState"
        case receiptURL = "receipt_url"
        case receiptURLCamel = "receiptUrl"
        case receiptExists = "receipt_exists"
        case receiptExistsCamel = "receiptExists"
        case payment
        case receipt
        case paymentReceipt
        case review
        case store
        case orderMenuList = "order_menu_list"
        case currentOrderStatus = "current_order_status"
        case currentOrderStatusCamel = "currentOrderStatus"
        case orderStatus = "order_status"
        case orderStatusCamel = "orderStatus"
        case orderStatusTimeline = "order_status_timeline"
        case paidAt
        case paidAtSnake = "paid_at"
        case createdAt
        case updatedAt
    }

    init(
        orderID: String,
        orderCode: String,
        totalPrice: Decimal,
        paymentLookupKey: String? = nil,
        paymentID: String? = nil,
        merchantUID: String? = nil,
        impUID: String? = nil,
        paymentStatus: String? = nil,
        paymentVerificationState: String? = nil,
        receiptURL: String? = nil,
        receiptExists: Bool? = nil,
        review: OrderReviewReferenceDTO?,
        store: StoreSummaryDTOOrder,
        orderMenuList: [OrderMenuQuantityResponseDTO],
        currentOrderStatus: String,
        orderStatusTimeline: [OrderStatusTimelineResponseDTO],
        paidAt: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.orderID = orderID
        self.orderCode = orderCode
        self.totalPrice = totalPrice
        self.paymentLookupKey = paymentLookupKey
        self.paymentID = paymentID
        self.merchantUID = merchantUID
        self.impUID = impUID
        self.paymentStatus = paymentStatus
        self.paymentVerificationState = paymentVerificationState
        self.receiptURL = receiptURL
        self.receiptExists = receiptExists
        self.review = review
        self.store = store
        self.orderMenuList = orderMenuList
        self.currentOrderStatus = currentOrderStatus
        self.orderStatusTimeline = orderStatusTimeline
        self.paidAt = paidAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(
        orderID: String,
        orderCode: String,
        totalPrice: Decimal,
        paymentLookupKey: String? = nil,
        paymentID: String? = nil,
        merchantUID: String? = nil,
        impUID: String? = nil,
        paymentStatus: String? = nil,
        receiptURL: String? = nil,
        receiptExists: Bool? = nil,
        review: OrderReviewReferenceDTO?,
        store: StoreSummaryDTOOrder,
        orderMenuList: [OrderMenuQuantityResponseDTO],
        currentOrderStatus: String,
        orderStatusTimeline: [OrderStatusTimelineResponseDTO],
        paidAt: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.init(
            orderID: orderID,
            orderCode: orderCode,
            totalPrice: totalPrice,
            paymentLookupKey: paymentLookupKey,
            paymentID: paymentID,
            merchantUID: merchantUID,
            impUID: impUID,
            paymentStatus: paymentStatus,
            paymentVerificationState: nil,
            receiptURL: receiptURL,
            receiptExists: receiptExists,
            review: review,
            store: store,
            orderMenuList: orderMenuList,
            currentOrderStatus: currentOrderStatus,
            orderStatusTimeline: orderStatusTimeline,
            paidAt: paidAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payment = try container.decodeIfPresent(OrderPaymentLookupDTO.self, forKey: .payment)
        let receipt = try container.decodeIfPresent(OrderPaymentLookupDTO.self, forKey: .receipt)
        let paymentReceipt = try container.decodeIfPresent(OrderPaymentLookupDTO.self, forKey: .paymentReceipt)

        orderID = try container.decode(String.self, forKey: .orderID)
        orderCode = try container.decode(String.self, forKey: .orderCode)
        totalPrice = try container.decodeFlexibleDecimal(forKey: .totalPrice)
        paymentLookupKey = try container.decodeTrimmedString(forKeys: [.paymentLookupKey, .paymentLookupKeyCamel])
            ?? payment?.paymentLookupKey
            ?? receipt?.paymentLookupKey
            ?? paymentReceipt?.paymentLookupKey
        paymentID = try container.decodeTrimmedString(forKeys: [.paymentID, .paymentIDCamel])
            ?? payment?.paymentID
            ?? receipt?.paymentID
            ?? paymentReceipt?.paymentID
        merchantUID = try container.decodeTrimmedString(forKeys: [.merchantUID, .merchantUIDCamel])
            ?? payment?.merchantUID
            ?? receipt?.merchantUID
            ?? paymentReceipt?.merchantUID
        impUID = try container.decodeTrimmedString(forKeys: [.impUID, .impUIDCamel])
            ?? payment?.impUID
            ?? receipt?.impUID
            ?? paymentReceipt?.impUID
        paymentStatus = try container.decodeTrimmedString(forKeys: [.paymentStatus, .paymentStatusCamel])
            ?? payment?.paymentStatus
            ?? receipt?.paymentStatus
            ?? paymentReceipt?.paymentStatus
        paymentVerificationState = try container.decodeTrimmedString(
            forKeys: [.paymentVerificationState, .paymentVerificationStateCamel]
        )
            ?? payment?.paymentVerificationState
            ?? receipt?.paymentVerificationState
            ?? paymentReceipt?.paymentVerificationState
        receiptURL = try container.decodeTrimmedString(forKeys: [.receiptURL, .receiptURLCamel])
            ?? payment?.receiptURL
            ?? receipt?.receiptURL
            ?? paymentReceipt?.receiptURL
        receiptExists = try container.decodeFlexibleBool(forKeys: [.receiptExists, .receiptExistsCamel])
            ?? payment?.receiptExists
            ?? receipt?.receiptExists
            ?? paymentReceipt?.receiptExists
        review = try container.decodeIfPresent(OrderReviewReferenceDTO.self, forKey: .review)
        store = try container.decode(StoreSummaryDTOOrder.self, forKey: .store)
        orderMenuList = try container.decodeIfPresent([OrderMenuQuantityResponseDTO].self, forKey: .orderMenuList) ?? []
        currentOrderStatus = try container.decodeTrimmedString(
            forKeys: [.currentOrderStatus, .currentOrderStatusCamel, .orderStatus, .orderStatusCamel]
        ) ?? "UNKNOWN"
        orderStatusTimeline = try container.decodeIfPresent([OrderStatusTimelineResponseDTO].self, forKey: .orderStatusTimeline) ?? []
        paidAt = try container.decodeIfPresent(String.self, forKey: .paidAt)
            ?? container.decodeIfPresent(String.self, forKey: .paidAtSnake)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

struct OrderPaymentLookupDTO: Decodable, Sendable {
    let paymentLookupKey: String?
    let paymentID: String?
    let merchantUID: String?
    let impUID: String?
    let paymentStatus: String?
    let paymentVerificationState: String?
    let receiptURL: String?
    let receiptExists: Bool?

    private enum CodingKeys: String, CodingKey {
        case paymentLookupKey = "payment_lookup_key"
        case paymentLookupKeyCamel = "paymentLookupKey"
        case paymentID = "payment_id"
        case paymentIDCamel = "paymentId"
        case merchantUID = "merchant_uid"
        case merchantUIDCamel = "merchantUid"
        case impUID = "imp_uid"
        case impUIDCamel = "impUid"
        case paymentStatus = "payment_status"
        case paymentStatusCamel = "paymentStatus"
        case paymentVerificationState = "payment_verification_state"
        case paymentVerificationStateCamel = "paymentVerificationState"
        case receiptURL = "receipt_url"
        case receiptURLCamel = "receiptUrl"
        case receiptExists = "receipt_exists"
        case receiptExistsCamel = "receiptExists"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paymentLookupKey = try container.decodeTrimmedString(forKeys: [.paymentLookupKey, .paymentLookupKeyCamel])
        paymentID = try container.decodeTrimmedString(forKeys: [.paymentID, .paymentIDCamel])
        merchantUID = try container.decodeTrimmedString(forKeys: [.merchantUID, .merchantUIDCamel])
        impUID = try container.decodeTrimmedString(forKeys: [.impUID, .impUIDCamel])
        paymentStatus = try container.decodeTrimmedString(forKeys: [.paymentStatus, .paymentStatusCamel])
        paymentVerificationState = try container.decodeTrimmedString(
            forKeys: [.paymentVerificationState, .paymentVerificationStateCamel]
        )
        receiptURL = try container.decodeTrimmedString(forKeys: [.receiptURL, .receiptURLCamel])
        receiptExists = try container.decodeFlexibleBool(forKeys: [.receiptExists, .receiptExistsCamel])
    }
}

struct OrderReviewReferenceDTO: Decodable, Sendable {
    let id: String
    let rating: Decimal
}

struct StoreSummaryDTOOrder: Decodable, Sendable {
    let id: String
    let category: String?
    let name: String
    let close: String?
    let storeImageURLs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case name
        case close
        case storeImageURLs = "store_image_urls"
    }
}

struct MenuResponseDTOOrder: Decodable, Sendable {
    let id: String
    let category: String?
    let name: String?
    let detailDescription: String?
    let price: Decimal?
    let tags: [String]
    let menuImageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case name
        case detailDescription = "description"
        case price
        case tags
        case menuImageURL = "menu_image_url"
    }
}

struct OrderMenuQuantityResponseDTO: Decodable, Sendable {
    let menu: MenuResponseDTOOrder
    let quantity: Int
}

struct OrderStatusTimelineResponseDTO: Decodable, Sendable {
    let status: String
    let completed: Bool
    let changedAt: String?
}

private extension KeyedDecodingContainer {
    func decodeTrimmedString(forKeys keys: [Key]) throws -> String? {
        for key in keys {
            if let value = try decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func decodeFlexibleBool(forKeys keys: [Key]) throws -> Bool? {
        for key in keys {
            if let value = try decodeIfPresent(Bool.self, forKey: key) {
                return value
            }
            if let value = try decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() {
                switch value {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    break
                }
            }
        }
        return nil
    }

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
