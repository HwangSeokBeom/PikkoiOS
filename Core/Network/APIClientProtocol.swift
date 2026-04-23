import Foundation

protocol APIClientProtocol: Sendable {
    func execute<ResponseDTO: Decodable & Sendable>(
        _ endpoint: Endpoint<ResponseDTO>
    ) async throws -> ResponseDTO
}
