import Foundation

enum OrderDetailAction: Equatable {
    case onAppear
    case retryTapped
    case storeTapped
    case reviewTapped
    case resumePendingPaymentTapped
    case paymentBridgeResult(CheckoutPaymentBridgeResult)
    case paymentBridgeDismissed
    case cancelConfirmed
    case loginRequiredTapped
}
