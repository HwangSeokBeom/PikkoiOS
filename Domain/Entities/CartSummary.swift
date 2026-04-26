import Foundation

struct CartSummary: Equatable, Sendable {
    let itemCount: Int
    let subtotalText: String

    static let empty = CartSummary(itemCount: 0, subtotalText: "0원")
}
