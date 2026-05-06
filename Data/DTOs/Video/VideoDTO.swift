import Foundation

struct VideoListResponseDTO: Decodable, Sendable {
    let data: [VideoResponseDTO]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case videos
        case items
        case results
        case nextCursor = "next_cursor"
    }

    init(data: [VideoResponseDTO], nextCursor: String?) {
        self.data = data
        self.nextCursor = Self.normalizedCursor(nextCursor)
    }

    init(from decoder: Decoder) throws {
        if let rootArray = try? decoder.singleValueContainer().decode([VideoResponseDTO].self) {
            self.init(data: rootArray, nextCursor: nil)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decodeIfPresent([VideoResponseDTO].self, forKey: .data)
            ?? container.decodeIfPresent([VideoResponseDTO].self, forKey: .videos)
            ?? container.decodeIfPresent([VideoResponseDTO].self, forKey: .items)
            ?? container.decodeIfPresent([VideoResponseDTO].self, forKey: .results)
            ?? []
        let nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        self.init(data: data, nextCursor: nextCursor)
    }

    private static func normalizedCursor(_ cursor: String?) -> String? {
        guard let cursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cursor.isEmpty,
              cursor != "0" else {
            return nil
        }

        return cursor
    }
}

struct VideoResponseDTO: Decodable, Sendable {
    let videoId: String
    let fileName: String
    let title: String
    let description: String
    let duration: Double
    let thumbnailURLPath: String
    let availableQualities: [String]
    let viewCount: Int
    let likeCount: Int
    let isLiked: Bool
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case videoIdSnake = "video_id"
        case videoIdCamel = "videoId"
        case id
        case underscoreId = "_id"
        case fileName = "file_name"
        case title
        case description
        case duration
        case thumbnailURLPath = "thumbnail_url"
        case availableQualities = "available_qualities"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case createdAt = "createdAt"
        case createdAtSnake = "created_at"
    }

    init(
        videoId: String,
        fileName: String,
        title: String,
        description: String,
        duration: Double,
        thumbnailURLPath: String,
        availableQualities: [String],
        viewCount: Int,
        likeCount: Int,
        isLiked: Bool,
        createdAt: String
    ) {
        self.videoId = videoId
        self.fileName = fileName
        self.title = title
        self.description = description
        self.duration = duration
        self.thumbnailURLPath = thumbnailURLPath
        self.availableQualities = availableQualities
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.isLiked = isLiked
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let videoId = Self.normalizedIdentifier(from: container)
        self.init(
            videoId: videoId,
            fileName: try container.decodeIfPresent(String.self, forKey: .fileName) ?? videoId,
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
            duration: try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0,
            thumbnailURLPath: try container.decodeIfPresent(String.self, forKey: .thumbnailURLPath) ?? "",
            availableQualities: try container.decodeIfPresent([String].self, forKey: .availableQualities) ?? [],
            viewCount: try container.decodeIfPresent(Int.self, forKey: .viewCount) ?? 0,
            likeCount: try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0,
            isLiked: try container.decodeIfPresent(Bool.self, forKey: .isLiked) ?? false,
            createdAt: try container.decodeIfPresent(String.self, forKey: .createdAt)
                ?? container.decodeIfPresent(String.self, forKey: .createdAtSnake)
                ?? ""
        )
    }

    private static func normalizedIdentifier(from container: KeyedDecodingContainer<CodingKeys>) -> String {
        for key in [CodingKeys.videoIdSnake, .videoIdCamel, .id, .underscoreId] {
            if let value = decodeIdentifier(from: container, forKey: key) {
                return value
            }
        }

        return ""
    }

    private static func decodeIdentifier(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedValue.isEmpty ? nil : normalizedValue
        }

        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }

        return nil
    }
}

struct StreamUrlResponseDTO: Decodable, Sendable {
    let videoId: String
    let streamURLPath: String
    let defaultQuality: String?
    let qualities: [VideoStreamQualityDTO]
    let subtitles: [VideoSubtitleDTO]

    private enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case videoIdCamel = "videoId"
        case streamURLPath = "stream_url"
        case streamURLCamel = "streamUrl"
        case url
        case defaultQuality = "default_quality"
        case defaultQualityCamel = "defaultQuality"
        case qualities
        case subtitles
    }

    init(
        videoId: String,
        streamURLPath: String,
        defaultQuality: String? = nil,
        qualities: [VideoStreamQualityDTO],
        subtitles: [VideoSubtitleDTO]
    ) {
        self.videoId = videoId
        self.streamURLPath = streamURLPath
        self.defaultQuality = defaultQuality
        self.qualities = qualities
        self.subtitles = subtitles
        Self.logDecodedStream(
            videoId: videoId,
            streamURLPath: streamURLPath,
            qualities: qualities
        )
    }

    init(
        videoId: String,
        streamURLPath: String,
        qualities: [VideoStreamQualityDTO],
        subtitles: [VideoSubtitleDTO]
    ) {
        self.init(
            videoId: videoId,
            streamURLPath: streamURLPath,
            defaultQuality: nil,
            qualities: qualities,
            subtitles: subtitles
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            videoId: try container.decodeIfPresent(String.self, forKey: .videoId)
                ?? container.decodeIfPresent(String.self, forKey: .videoIdCamel)
                ?? "",
            streamURLPath: try container.decodeIfPresent(String.self, forKey: .streamURLPath)
                ?? container.decodeIfPresent(String.self, forKey: .streamURLCamel)
                ?? container.decodeIfPresent(String.self, forKey: .url)
                ?? "",
            defaultQuality: try container.decodeIfPresent(String.self, forKey: .defaultQuality)
                ?? container.decodeIfPresent(String.self, forKey: .defaultQualityCamel),
            qualities: try container.decodeIfPresent([VideoStreamQualityDTO].self, forKey: .qualities) ?? [],
            subtitles: try container.decodeIfPresent([VideoSubtitleDTO].self, forKey: .subtitles) ?? []
        )
    }

    private static func logDecodedStream(
        videoId: String,
        streamURLPath: String,
        qualities: [VideoStreamQualityDTO]
    ) {
        let logger = Logger(category: "VideoStreamDTO")
        let streamDescriptor = VideoURLLogDescriptor(rawValue: streamURLPath)
        logger.debug(
            "[VideoStreamDTO] videoID=\(videoId) streamURLRawExists=\(!streamURLPath.isEmpty) streamURLPath=\(streamDescriptor.path) rawQueryExists=\(streamDescriptor.queryExists) queryKeys=\(streamDescriptor.queryKeys) rawQueryKeyCount=\(streamDescriptor.queryKeyCount) rawQueryLength=\(streamDescriptor.rawQueryLength) percentEncodedQueryLength=\(streamDescriptor.percentEncodedQueryLength) tokenLength=\(streamDescriptor.tokenValueLength)"
        )
        logger.debug(
            "[VideoStreamDTO] quality=auto rawPath=\(streamDescriptor.path) queryExists=\(streamDescriptor.queryExists) queryKeys=\(streamDescriptor.queryKeys) queryKeyCount=\(streamDescriptor.queryKeyCount)"
        )

        for quality in qualities {
            let descriptor = VideoURLLogDescriptor(rawValue: quality.urlPath)
            logger.debug(
                "[VideoStreamDTO] quality=\(quality.quality) rawPath=\(descriptor.path) queryExists=\(descriptor.queryExists) queryKeys=\(descriptor.queryKeys) queryKeyCount=\(descriptor.queryKeyCount)"
            )
        }
    }
}

struct VideoStreamQualityDTO: Decodable, Sendable {
    let quality: String
    let urlPath: String
    let label: String?
    let resolution: String?
    let bitrate: String?

    private enum CodingKeys: String, CodingKey {
        case quality
        case label
        case resolution
        case bitrate
        case urlPath = "url"
        case streamURLPath = "stream_url"
    }

    init(
        quality: String,
        urlPath: String,
        label: String? = nil,
        resolution: String? = nil,
        bitrate: String? = nil
    ) {
        self.quality = quality
        self.urlPath = urlPath
        self.label = label
        self.resolution = resolution
        self.bitrate = bitrate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        self.quality = try container.decodeIfPresent(String.self, forKey: .quality)
            ?? label
            ?? ""
        self.urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath)
            ?? container.decodeIfPresent(String.self, forKey: .streamURLPath)
            ?? ""
        self.label = label
        self.resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        self.bitrate = Self.decodeFlexibleString(from: container, forKey: .bitrate)
    }

    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

#if DEBUG
enum VideoStreamingDebugLogger {
    static func logAPIResponse(videoId: String, response: StreamUrlResponseDTO) {
        print("[VideoStreamingDebug] videoId=\(videoId)")
        print("[VideoStreamingDebug] response.stream_url=\(redactedURLString(response.streamURLPath))")
        logURLComponents(label: "response.stream_url", rawValue: response.streamURLPath)
        print("[VideoStreamingDebug] qualities.count=\(response.qualities.count)")
        for (index, quality) in response.qualities.enumerated() {
            print(
                "[VideoStreamingDebug] qualities[\(index)] label=\(quality.label ?? quality.quality) resolution=\(quality.resolution ?? "-") bitrate=\(quality.bitrate ?? "-") stream_url=\(redactedURLString(quality.urlPath))"
            )
            logURLComponents(label: "qualities[\(index)].stream_url", rawValue: quality.urlPath)
        }
    }

    static func logSelected(source: String, quality: String, url: URL) {
        print("[VideoStreamingDebug] selectedSource=\(source)")
        print("[VideoStreamingDebug] selectedQuality=\(quality)")
        print("[VideoStreamingDebug] selectedURL=\(redactedURLString(url.absoluteString))")
        logURLComponents(label: "selectedURL", url: url)
    }

    static func logFinalPlayerURL(action: String, url: URL) {
        print("[VideoStreamingDebug] \(action) url=\(redactedURLString(url.absoluteString))")
        logURLComponents(label: action, url: url)
    }

    static func logURLComponents(label: String, url: URL) {
        logURLComponents(label: label, rawValue: url.absoluteString)
    }

    static func logURLComponents(label: String, rawValue: String) {
        guard let components = URLComponents(string: rawValue) else {
            print("[VideoStreamingDebug] \(label).urlComponents=false")
            return
        }

        let queryNames = queryItemNames(from: components.percentEncodedQuery)
        print("[VideoStreamingDebug] \(label).hasToken=\(queryNames.contains("token"))")
        print("[VideoStreamingDebug] \(label).queryItems=\(queryNames.isEmpty ? "nil" : queryNames.joined(separator: ","))")
        print(
            "[VideoStreamingDebug] \(label).scheme=\(components.scheme ?? "nil") host=\(components.host ?? "nil") path=\(components.percentEncodedPath.removingPercentEncoding ?? components.path)"
        )
    }

    private static func queryItemNames(from percentEncodedQuery: String?) -> [String] {
        guard let percentEncodedQuery,
              !percentEncodedQuery.isEmpty else {
            return []
        }

        return percentEncodedQuery
            .split(separator: "&")
            .compactMap { rawPair -> String? in
                let rawName = rawPair.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                let name = rawName.removingPercentEncoding ?? rawName
                return name.isEmpty ? nil : name
            }
    }

    private static func redactedURLString(_ rawValue: String) -> String {
        guard var components = URLComponents(string: rawValue) else {
            return rawValue.contains("?") ? "\(rawValue.components(separatedBy: "?").first ?? rawValue)?<redacted>" : rawValue
        }

        guard components.percentEncodedQuery?.isEmpty == false else {
            return rawValue
        }

        components.percentEncodedQuery = nil
        return "\(components.string ?? rawValue)?<redacted>"
    }
}
#endif

struct VideoSubtitleDTO: Decodable, Sendable {
    let language: String
    let name: String
    let isDefault: Bool
    let urlPath: String

    private enum CodingKeys: String, CodingKey {
        case language
        case name
        case isDefault = "is_default"
        case urlPath = "url"
    }
}

struct VideoLikeRequestDTO: Encodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}

struct VideoLikeResponseDTO: Decodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}
