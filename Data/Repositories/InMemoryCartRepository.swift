import Foundation

struct InMemoryCartRepository: CartRepository {
    func fetchCartSummary(for session: UserSession?) async throws -> CartSummary {
        guard session != nil else {
            return .empty
        }

        // TODO: Replace with server-backed cart hydration.
        return CartSummary(itemCount: 0, subtotalText: "$0")
    }
}
