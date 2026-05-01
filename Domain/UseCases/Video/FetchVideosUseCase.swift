import Foundation

struct FetchVideosUseCase: Sendable {
    private let repository: any VideoRepository

    init(repository: any VideoRepository) {
        self.repository = repository
    }

    func execute(nextCursor: String? = nil, limit: Int = 5) async throws -> CursorPage<Video> {
        try await repository.fetchVideos(nextCursor: nextCursor, limit: limit)
    }
}
