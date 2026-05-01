import Foundation

enum VideoEndpoint {
    static func list(nextCursor: String?, limit: Int) -> Endpoint<VideoListResponseDTO> {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let nextCursor, !nextCursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            query.insert(URLQueryItem(name: "next", value: nextCursor), at: 0)
        }

        return Endpoint<VideoListResponseDTO>(
            path: "/v1/videos",
            method: .get,
            query: query,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
    }

    static func stream(videoId: String) throws -> Endpoint<StreamUrlResponseDTO> {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoId.isEmpty else {
            throw VideoStreamRequestError.invalidVideoId
        }

        return Endpoint<StreamUrlResponseDTO>(
            path: "/v1/videos/\(normalizedVideoId)/stream",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
    }

    static func like(videoId: String, isLiked: Bool) throws -> Endpoint<VideoLikeResponseDTO> {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoId.isEmpty else {
            throw VideoStreamRequestError.invalidVideoId
        }

        return Endpoint<VideoLikeResponseDTO>(
            path: "/v1/videos/\(normalizedVideoId)/like",
            method: .post,
            body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(VideoLikeRequestDTO(likeStatus: isLiked))),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
    }
}
