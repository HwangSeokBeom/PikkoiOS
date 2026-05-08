import Foundation

struct VideoRepositoryImpl: VideoRepository {
    private let remoteDataSource: any VideoRemoteDataSourceProtocol
    private let mapper: VideoMapper
    private let streamRequestDeduplicator = VideoStreamRequestDeduplicator()

    init(
        remoteDataSource: any VideoRemoteDataSourceProtocol,
        mapper: VideoMapper
    ) {
        self.remoteDataSource = remoteDataSource
        self.mapper = mapper
    }

    func fetchVideos(nextCursor: String?, limit: Int) async throws -> CursorPage<Video> {
        let response = try await remoteDataSource.fetchVideos(nextCursor: nextCursor, limit: limit)
        return mapper.mapPage(response)
    }

    func fetchVideoStream(videoId: String) async throws -> VideoStream {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await streamRequestDeduplicator.value(for: normalizedVideoId) {
            let response = try await remoteDataSource.fetchVideoStream(videoId: normalizedVideoId)
            return try mapper.map(response)
        }
    }

    func updateLikeStatus(videoId: String, isLiked: Bool) async throws -> Bool {
        let response = try await remoteDataSource.updateLikeStatus(videoId: videoId, isLiked: isLiked)
        return response.likeStatus
    }
}

private actor VideoStreamRequestDeduplicator {
    private struct CacheEntry {
        let stream: VideoStream
        let storedAt: Date
    }

    private let logger = Logger(category: "VideoAPI")
    private let ttl: TimeInterval = 8
    private var inFlight: [String: Task<VideoStream, Error>] = [:]
    private var cache: [String: CacheEntry] = [:]

    func value(
        for videoId: String,
        operation: @Sendable @escaping () async throws -> VideoStream
    ) async throws -> VideoStream {
        let key = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return try await operation()
        }

        let now = Date()
        if let entry = cache[key],
           now.timeIntervalSince(entry.storedAt) <= ttl {
            logger.debug("[VideoAPI] stream cache hit videoId=\(key) ttlSeconds=\(Int(ttl))")
            return entry.stream
        }

        if let task = inFlight[key] {
            logger.debug("[VideoAPI] stream request dedupe join videoId=\(key)")
            return try await task.value
        }

        let task = Task {
            try await operation()
        }
        inFlight[key] = task
        do {
            let stream = try await task.value
            inFlight[key] = nil
            cache[key] = CacheEntry(stream: stream, storedAt: Date())
            pruneCache(now: Date())
            return stream
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private func pruneCache(now: Date) {
        cache = cache.filter { now.timeIntervalSince($0.value.storedAt) <= ttl }
    }
}
