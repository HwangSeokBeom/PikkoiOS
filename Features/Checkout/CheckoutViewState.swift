import Foundation

enum CheckoutCompletionState: Equatable {
    case none
    case orderCreated
    case paymentValidated
    case validationPending
}

enum CheckoutPaymentStage: Equatable {
    case idle
    case validatingPrice
    case creatingOrder
    case paymentPrepared
    case presentingPayment
    case paymentCallbackReceived
    case validatingPayment
    case paymentCompleted
    case paymentCanceled
    case paymentFailed
    case paymentValidationFailed

    var blocksPrimaryAction: Bool {
        switch self {
        case .validatingPrice, .creatingOrder, .paymentPrepared, .presentingPayment, .paymentCallbackReceived, .validatingPayment, .paymentCompleted:
            return true
        case .idle, .paymentCanceled, .paymentFailed, .paymentValidationFailed:
            return false
        }
    }

    var blocksBackNavigation: Bool {
        switch self {
        case .paymentPrepared, .presentingPayment, .paymentCallbackReceived, .validatingPayment, .paymentCompleted:
            return true
        case .idle, .validatingPrice, .creatingOrder, .paymentCanceled, .paymentFailed, .paymentValidationFailed:
            return false
        }
    }
}

struct CheckoutPaymentBridgeContext: Equatable, Sendable {
    let orderID: String
    let orderCode: String
    let paymentRequest: PaymentGatewayRequest
}

enum CheckoutPaymentBridgeResult: Equatable, Sendable {
    case succeeded(impUID: String, merchantUID: String?)
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
    var isPaymentInProgress = false
    var isVerifyingPayment = false
    var totalPriceText = "0원"
    var paymentStage: CheckoutPaymentStage = .idle
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
    var paymentWarningMessage: String?
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
