import Foundation
import WebKit

struct PaymentGatewayRequest: Equatable, Sendable {
    let orderID: String
    let merchantUID: String
    let amount: Decimal
    let orderName: String
    let buyerName: String
    let pg: String
    let pgID: String?
    let payMethod: String
    let appScheme: String
    let userCode: String
    let isTestMode: Bool
}

struct PaymentGatewayResult: Equatable, Sendable {
    let success: Bool
    let impUID: String?
    let merchantUID: String?
    let errorCode: String?
    let errorMessage: String?
    let rawDescription: String?
}

@MainActor
protocol PaymentGateway: AnyObject {
    func requestPayment(
        on webView: WKWebView,
        request: PaymentGatewayRequest,
        completion: @escaping @MainActor (PaymentGatewayResult) -> Void
    )

    func close()
}
