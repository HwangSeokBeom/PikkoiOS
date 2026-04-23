import Foundation

protocol AuthRepository: Sendable {
    func restoreSession() async throws -> UserSession?
    func signInStub() async throws -> UserSession
}
