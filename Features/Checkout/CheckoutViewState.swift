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
    case recoverablePending

    var blocksPrimaryAction: Bool {
        switch self {
        case .validatingPrice, .creatingOrder, .paymentPrepared, .presentingPayment, .paymentCallbackReceived, .validatingPayment, .paymentCompleted:
            return true
        case .idle, .paymentCanceled, .paymentFailed, .paymentValidationFailed, .recoverablePending:
            return false
        }
    }

    var blocksBackNavigation: Bool {
        switch self {
        case .paymentPrepared, .presentingPayment, .paymentCallbackReceived, .validatingPayment, .paymentCompleted:
            return true
        case .idle, .validatingPrice, .creatingOrder, .paymentCanceled, .paymentFailed, .paymentValidationFailed, .recoverablePending:
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

struct CheckoutPaymentConfigurationDiagnosticViewState: Equatable, Sendable {
    let source: String
    let state: String
    let rawMasked: String
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
    var isPaymentConfigurationBlocked = false
    var paymentConfigurationDiagnosticMessage: String?
    var paymentConfigurationDiagnostic: CheckoutPaymentConfigurationDiagnosticViewState?
    var isPrimaryLoading = false
    var canRouteToOrderHistoryFromPrimary = false
    var createdOrderID: String?
    var createdOrderCode: String?
    var completionState: CheckoutCompletionState = .none
    var paymentBridgeContext: CheckoutPaymentBridgeContext?
    var recoverablePaymentSession: PendingPaymentSession?
    var errorMessage: String?
    var successMessage: String?
    var paymentWarningMessage: String?
    var isEmpty = true

    var showsCompletionView: Bool {
        completionState != .none && createdOrderID != nil
    }

    init(
        title: String = "Checkout",
        storeName: String = "",
        summaryText: String = "",
        addressSummaryText: String = "",
        paymentMethodSummaryText: String = "",
        couponSummaryText: String = "",
        pickupMemo: String = "",
        items: [CheckoutItemViewState] = [],
        validationIssues: [CheckoutValidationIssueViewState] = [],
        isValidatingPrice: Bool = false,
        isSubmittingOrder: Bool = false,
        isPaymentInProgress: Bool = false,
        isVerifyingPayment: Bool = false,
        totalPriceText: String = "0원",
        paymentStage: CheckoutPaymentStage = .idle,
        primaryActionTitle: String = "주문 생성하기",
        isPrimaryEnabled: Bool = false,
        isPaymentConfigurationBlocked: Bool = false,
        paymentConfigurationDiagnosticMessage: String? = nil,
        paymentConfigurationDiagnostic: CheckoutPaymentConfigurationDiagnosticViewState? = nil,
        isPrimaryLoading: Bool = false,
        canRouteToOrderHistoryFromPrimary: Bool = false,
        createdOrderID: String? = nil,
        createdOrderCode: String? = nil,
        completionState: CheckoutCompletionState = .none,
        paymentBridgeContext: CheckoutPaymentBridgeContext? = nil,
        recoverablePaymentSession: PendingPaymentSession? = nil,
        errorMessage: String? = nil,
        successMessage: String? = nil,
        paymentWarningMessage: String? = nil,
        isEmpty: Bool = true
    ) {
        self.title = title
        self.storeName = storeName
        self.summaryText = summaryText
        self.addressSummaryText = addressSummaryText
        self.paymentMethodSummaryText = paymentMethodSummaryText
        self.couponSummaryText = couponSummaryText
        self.pickupMemo = pickupMemo
        self.items = items
        self.validationIssues = validationIssues
        self.isValidatingPrice = isValidatingPrice
        self.isSubmittingOrder = isSubmittingOrder
        self.isPaymentInProgress = isPaymentInProgress
        self.isVerifyingPayment = isVerifyingPayment
        self.totalPriceText = totalPriceText
        self.paymentStage = paymentStage
        self.primaryActionTitle = primaryActionTitle
        self.isPrimaryEnabled = isPrimaryEnabled
        self.isPaymentConfigurationBlocked = isPaymentConfigurationBlocked
        self.paymentConfigurationDiagnosticMessage = paymentConfigurationDiagnosticMessage
        self.paymentConfigurationDiagnostic = paymentConfigurationDiagnostic
        self.isPrimaryLoading = isPrimaryLoading
        self.canRouteToOrderHistoryFromPrimary = canRouteToOrderHistoryFromPrimary
        self.createdOrderID = createdOrderID
        self.createdOrderCode = createdOrderCode
        self.completionState = completionState
        self.paymentBridgeContext = paymentBridgeContext
        self.recoverablePaymentSession = recoverablePaymentSession
        self.errorMessage = errorMessage
        self.successMessage = successMessage
        self.paymentWarningMessage = paymentWarningMessage
        self.isEmpty = isEmpty
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
