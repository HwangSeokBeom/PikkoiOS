import Foundation

struct FetchVideoStreamUseCase: Sendable {
    private let repository: any VideoRepository

    init(repository: any VideoRepository) {
        self.repository = repository
    }

    func execute(videoId: String) async throws -> VideoStream {
        try await repository.fetchVideoStream(videoId: videoId)
    }
}
