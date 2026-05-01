import Foundation

struct SetVideoLikeUseCase: Sendable {
    private let repository: any VideoRepository

    init(repository: any VideoRepository) {
        self.repository = repository
    }

    func execute(videoId: String, isLiked: Bool) async throws -> Bool {
        try await repository.updateLikeStatus(videoId: videoId, isLiked: isLiked)
    }
}
