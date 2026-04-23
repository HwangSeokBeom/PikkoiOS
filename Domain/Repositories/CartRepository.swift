import Foundation

protocol CartRepository: Sendable {
    func fetchCartSummary(for session: UserSession?) async throws -> CartSummary
}
