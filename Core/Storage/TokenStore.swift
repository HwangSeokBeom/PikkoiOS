import Foundation

struct StoredTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

protocol TokenStore: Sendable {
    func loadTokens() async throws -> StoredTokens?
    func saveTokens(_ tokens: StoredTokens) async throws
    func clearTokens() async throws
}
