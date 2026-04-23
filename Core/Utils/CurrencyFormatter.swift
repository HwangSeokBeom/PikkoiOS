import Foundation

struct CurrencyFormatter: Sendable {
    func string(
        from amount: Decimal,
        currencyCode: String = "KRW",
        locale: Locale = Locale(identifier: "ko_KR")
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = locale
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
