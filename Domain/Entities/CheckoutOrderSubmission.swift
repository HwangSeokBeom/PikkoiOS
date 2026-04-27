import Foundation

struct CheckoutOrderSubmission: Equatable, Sendable {
    let storeID: String
    let storeName: String
    let items: [CheckoutOrderMenuSubmission]
    let totalPriceAmount: Decimal
    let address: CheckoutAddress?
    let paymentMethod: CheckoutPaymentMethod
    let coupon: CheckoutCoupon?
    let pickupMemo: String
    let paymentMethodID: String?
    let paymentProvider: CheckoutPaymentProvider?
    let couponID: String?

    init(
        draft: CheckoutDraft,
        address: CheckoutAddress?,
        paymentMethod: CheckoutPaymentMethod,
        coupon: CheckoutCoupon?,
        pickupMemo: String
    ) {
        self.storeID = draft.storeID
        self.storeName = draft.storeName
        self.items = draft.items.map {
            CheckoutOrderMenuSubmission(
                menuID: $0.menuID,
                menuName: $0.menuName,
                quantity: $0.quantity,
                optionSummaryText: $0.optionSummaryText,
                imagePath: $0.imagePath,
                unitPriceAmount: $0.unitPriceAmount
            )
        }
        self.totalPriceAmount = draft.subtotalAmount
        self.address = address
        self.paymentMethod = paymentMethod
        self.coupon = coupon
        self.pickupMemo = pickupMemo
        self.paymentMethodID = paymentMethod.identifier
        self.paymentProvider = paymentMethod.paymentProvider
        self.couponID = coupon?.code
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}

struct CheckoutSubmissionInput: Equatable, Sendable {
    let address: CheckoutAddress?
    let paymentMethod: CheckoutPaymentMethod
    let coupon: CheckoutCoupon?
    let pickupMemo: String
}

struct CheckoutOrderMenuSubmission: Equatable, Sendable {
    let menuID: String
    let menuName: String
    let quantity: Int
    let optionSummaryText: String?
    let imagePath: String?
    let unitPriceAmount: Decimal
}

struct CheckoutAddress: Equatable, Sendable {
    let label: String
    let roadAddress: String
    let detailAddress: String?
    let postalCode: String?

    var summaryText: String {
        if let detailAddress, !detailAddress.isEmpty {
            return "\(roadAddress) · \(detailAddress)"
        }
        return roadAddress
    }

    static let placeholder = CheckoutAddress(
        label: "수령지 미설정",
        roadAddress: "결제 단계에서 입력 예정",
        detailAddress: nil,
        postalCode: nil
    )
}

enum CheckoutPaymentProvider: String, Equatable, Sendable {
    case portOne
}

enum CheckoutPaymentMethod: Equatable, Sendable {
    case card
    case payOnPickup

    var summaryText: String {
        switch self {
        case .card:
            return "카드 결제 (PG 연동 예정)"
        case .payOnPickup:
            return "현장 결제"
        }
    }

    var identifier: String? {
        switch self {
        case .card:
            return "card"
        case .payOnPickup:
            return "pay_on_pickup"
        }
    }

    var paymentProvider: CheckoutPaymentProvider? {
        switch self {
        case .card:
            return .portOne
        case .payOnPickup:
            return nil
        }
    }
}

struct CheckoutCoupon: Equatable, Sendable {
    let code: String
    let title: String
    let discountAmount: Decimal

    var summaryText: String {
        "\(title) · -\(formatWon(discountAmount))"
    }

    private func formatWon(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ko_KR")
        return "\(formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")원"
    }
}
