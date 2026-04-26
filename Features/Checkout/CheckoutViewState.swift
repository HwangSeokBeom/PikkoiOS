import Foundation

enum CheckoutCompletionState: Equatable {
    case none
    case orderCreated
    case paymentValidated
    case validationPending
}

struct CheckoutPaymentBridgeContext: Equatable, Sendable {
    let orderID: String
    let orderCode: String
    let initialURL: URL
    let redirectURL: URL?
}

enum CheckoutPaymentBridgeResult: Equatable, Sendable {
    case succeeded(impUID: String)
    case failed(message: String)
    case cancelled
    case missingImpUID
}

struct CheckoutViewState: Equatable {
    var title = "Checkout"
    var storeName = ""
    var summaryText = ""
    var addressSummaryText = ""
    var paymentMethodSummaryText = ""
    var couponSummaryText = ""
    var pickupMemo = ""
    var items: [CheckoutItemViewState] = []
    var validationIssues: [CheckoutValidationIssueViewState] = []
    var isValidatingPrice = false
    var isSubmittingOrder = false
    var totalPriceText = "0원"
    var primaryActionTitle = "주문 생성하기"
    var isPrimaryEnabled = false
    var isPrimaryLoading = false
    var canRouteToOrderHistoryFromPrimary = false
    var createdOrderID: String?
    var createdOrderCode: String?
    var completionState: CheckoutCompletionState = .none
    var paymentBridgeContext: CheckoutPaymentBridgeContext?
    var errorMessage: String?
    var successMessage: String?
    var isEmpty = true

    var showsCompletionView: Bool {
        completionState != .none && createdOrderID != nil
    }
}

struct CheckoutItemViewState: Identifiable, Equatable {
    let id: String
    let name: String
    let optionSummaryText: String
    let quantity: Int
    let unitPriceText: String
    let subtotalText: String
    var validationMessage: String?
}

struct CheckoutValidationIssueViewState: Identifiable, Equatable {
    let id: String
    let menuID: String?
    let title: String
    let message: String
    let isBlocking: Bool
}
