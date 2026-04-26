import Foundation

enum CheckoutAction {
    case onAppear
    case pickupMemoChanged(String)
    case primaryButtonTapped
    case orderHistoryTapped
    case paymentBridgeResult(CheckoutPaymentBridgeResult)
    case paymentBridgeDismissed
}
