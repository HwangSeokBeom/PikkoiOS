import Foundation
import WebKit
import iamport_ios

@MainActor
final class PortOnePaymentGateway: PaymentGateway {
    func requestPayment(
        on webView: WKWebView,
        request: PaymentGatewayRequest,
        completion: @escaping @MainActor (PaymentGatewayResult) -> Void
    ) {
        let payment = IamportPayment(
            pg: makePgRawName(pg: request.pg, pgID: request.pgID),
            merchant_uid: request.merchantUID,
            amount: amountString(from: request.amount)
        )
        payment.pay_method = request.payMethod
        payment.name = request.orderName
        payment.buyer_name = request.buyerName
        payment.app_scheme = request.appScheme

        Iamport.shared.paymentWebView(
            webViewMode: webView,
            userCode: request.userCode,
            payment: payment
        ) { response in
            let result = PaymentGatewayResult(
                success: response?.success == true,
                impUID: Self.normalized(response?.imp_uid),
                merchantUID: Self.normalized(response?.merchant_uid),
                errorCode: Self.normalized(response?.error_code),
                errorMessage: Self.normalized(response?.error_msg),
                rawDescription: response.map(String.init(describing:))
            )

            Task { @MainActor in
                completion(result)
            }
        }
    }

    func close() {
        Iamport.shared.close()
    }

    private func makePgRawName(pg: String, pgID: String?) -> String {
        if let convertedPG = PG.convertPG(pgString: pg) {
            return convertedPG.makePgRawName(pgId: pgID)
        }

        let trimmedPG = pg.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPGID = pgID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedPGID, !trimmedPGID.isEmpty else {
            return trimmedPG
        }
        return "\(trimmedPG).\(trimmedPGID)"
    }

    private func amountString(from amount: Decimal) -> String {
        let number = amount as NSDecimalNumber
        return number.stringValue
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
