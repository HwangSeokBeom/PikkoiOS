import Foundation

struct VideoMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let dateParser: DateParser
    private let logger = Logger(category: "VideoMapping")
    private var videoURLResolver: VideoURLResolver {
        VideoURLResolver(fileURLResolver: fileURLResolver, logger: logger)
    }

    init(
        fileURLResolver: any AuthorizedFileURLResolving,
        dateParser: DateParser = DateParser()
    ) {
        self.fileURLResolver = fileURLResolver
        self.dateParser = dateParser
    }

    func mapPage(_ dto: VideoListResponseDTO) -> CursorPage<Video> {
        var seenIDs = Set<String>()
        var items: [Video] = []
        var droppedEmptyIDCount = 0
        var droppedDuplicateIDCount = 0

        for videoDTO in dto.data {
            let videoID = videoDTO.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !videoID.isEmpty else {
                droppedEmptyIDCount += 1
                logger.warning("[VideoMapping] dropped video because id is empty title=\(videoDTO.title)")
                continue
            }

            guard seenIDs.insert(videoID).inserted else {
                droppedDuplicateIDCount += 1
                logger.warning("[VideoMapping] duplicated videoId dropped videoId=\(videoID)")
                continue
            }

            items.append(map(videoDTO, normalizedVideoId: videoID))
        }

        logger.debug(
            "[VideoMapping] mapped count=\(items.count) droppedEmptyId=\(droppedEmptyIDCount) droppedDuplicateId=\(droppedDuplicateIDCount)"
        )

        return CursorPage(
            items: items,
            nextCursor: normalize(cursor: dto.nextCursor)
        )
    }

    func map(_ dto: VideoResponseDTO) -> Video {
        map(dto, normalizedVideoId: dto.videoId.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func map(_ dto: VideoResponseDTO, normalizedVideoId: String) -> Video {
        Video(
            videoId: normalizedVideoId,
            fileName: dto.fileName,
            title: dto.title.pikkoSanitizedDisplayText,
            description: dto.description.pikkoSanitizedDisplayText,
            duration: dto.duration,
            thumbnailURL: resolveAbsoluteString(dto.thumbnailURLPath),
            availableQualities: dto.availableQualities,
            viewCount: dto.viewCount,
            likeCount: dto.likeCount,
            isLiked: dto.isLiked,
            createdAt: dateParser.parseISO8601(dto.createdAt)
        )
    }

    func map(_ dto: StreamUrlResponseDTO) throws -> VideoStream {
        let streamURL = try resolvePlaybackURL(dto.streamURLPath, quality: "auto")
        return VideoStream(
            videoId: dto.videoId,
            streamURL: streamURL,
            streamURLPath: dto.streamURLPath,
            defaultQuality: normalizedDefaultQuality(dto.defaultQuality),
            qualities: try mapQualities(dto.qualities, streamURL: streamURL),
            subtitles: try dto.subtitles.map {
                VideoSubtitle(
                    language: $0.language,
                    name: $0.name,
                    isDefault: $0.isDefault,
                    url: try resolveURL($0.urlPath),
                    format: VideoSubtitleFormat(rawValue: $0.format)
                )
            }
        )
    }

    private func mapQualities(_ dtoQualities: [VideoStreamQualityDTO], streamURL: URL) throws -> [VideoStreamQuality] {
        let priority = ["1080p": 0, "720p": 1, "480p": 2]
        var seenQualities = Set<String>()
        var mappedQualities: [VideoStreamQuality] = []

        for dtoQuality in dtoQualities {
            let quality = dtoQuality.quality.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlPath = dtoQuality.urlPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quality.isEmpty,
                  quality != "auto",
                  !urlPath.isEmpty,
                  seenQualities.insert(quality).inserted else {
                continue
            }

            mappedQualities.append(
                VideoStreamQuality(
                    quality: quality,
                    url: try resolvePlaybackURL(urlPath, quality: quality, streamURLForQueryFallback: streamURL),
                    urlPath: urlPath
                )
            )
        }

        return mappedQualities.sorted {
            let lhsPriority = priority[$0.quality] ?? Int.max
            let rhsPriority = priority[$1.quality] ?? Int.max
            if lhsPriority == rhsPriority {
                return $0.quality < $1.quality
            }
            return lhsPriority < rhsPriority
        }
    }

    private func normalizedDefaultQuality(_ quality: String?) -> String? {
        guard let quality = quality?.trimmingCharacters(in: .whitespacesAndNewlines),
              !quality.isEmpty else {
            return nil
        }

        return quality
    }

    private func normalize(cursor: String?) -> String? {
        guard let cursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cursor.isEmpty,
              cursor != "0" else {
            return nil
        }

        return cursor
    }

    private func resolveAbsoluteString(_ path: String) -> String? {
        guard let url = try? resolveURL(path) else {
            return nil
        }
        return url.absoluteString
    }

    private func resolveURL(_ path: String) throws -> URL {
        try fileURLResolver.resolveURL(from: path)
    }

    private func resolvePlaybackURL(
        _ path: String,
        quality: String,
        streamURLForQueryFallback: URL? = nil
    ) throws -> URL {
        try videoURLResolver.resolve(
            rawURLString: path,
            quality: quality,
            streamURLForQueryFallback: streamURLForQueryFallback
        )
    }
}

struct VideoURLResolver: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let logger: Logger

    init(fileURLResolver: any AuthorizedFileURLResolving, logger: Logger = Logger(category: "VideoURLResolve")) {
        self.fileURLResolver = fileURLResolver
        self.logger = logger
    }

    func resolve(
        rawURLString: String,
        quality: String,
        streamURLForQueryFallback: URL? = nil
    ) throws -> URL {
        let resolvedURL = try fileURLResolver.resolveURL(from: rawURLString)
        let queryFixedURL = copyQueryIfNeeded(to: resolvedURL, from: streamURLForQueryFallback)
        let normalizedResult = HLSStreamPathNormalizer.normalize(url: queryFixedURL)
        let rawDescriptor = VideoURLLogDescriptor(rawValue: rawURLString)
        let resolvedDescriptor = VideoURLLogDescriptor(url: normalizedResult.url)
        let strategy = resolveStrategy(
            for: rawURLString,
            copiedQuery: resolvedURL.absoluteString != queryFixedURL.absoluteString,
            normalizedPath: normalizedResult.normalization.didChange
        )
        logger.debug(
            "[VideoURLResolve] quality=\(quality) rawPath=\(rawDescriptor.path) originalPath=\(normalizedResult.normalization.originalPath) normalizedPath=\(normalizedResult.normalization.normalizedPath) pathNormalization=\(normalizedResult.normalization.action.rawValue) resolvedScheme=\(resolvedDescriptor.scheme) resolvedHost=\(resolvedDescriptor.host) resolvedPort=\(resolvedDescriptor.port) resolvedPath=\(resolvedDescriptor.path) resolvedExt=\(resolvedDescriptor.ext) queryExists=\(resolvedDescriptor.queryExists) queryKeys=\(resolvedDescriptor.queryKeys) queryKeyCount=\(resolvedDescriptor.queryKeyCount) rawQueryLength=\(resolvedDescriptor.rawQueryLength) percentEncodedQueryLength=\(resolvedDescriptor.percentEncodedQueryLength) rawTokenLength=\(rawDescriptor.tokenValueLength) resolvedTokenLength=\(resolvedDescriptor.tokenValueLength) tokenLengthPreserved=\(rawDescriptor.tokenValueLength == 0 || rawDescriptor.tokenValueLength == resolvedDescriptor.tokenValueLength) maskedQuery=\(resolvedDescriptor.maskedQuery) strategy=\(strategy)"
        )
        return normalizedResult.url
    }

    private func copyQueryIfNeeded(to url: URL, from streamURL: URL?) -> URL {
        guard !hasQuery(url),
              let streamURL,
              let streamComponents = URLComponents(url: streamURL, resolvingAgainstBaseURL: false),
              let streamQuery = streamComponents.percentEncodedQuery,
              !streamQuery.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.percentEncodedQuery = streamQuery
        return components.url ?? url
    }

    private func hasQuery(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.isEmpty == false
    }

    private func resolveStrategy(for rawURLString: String, copiedQuery: Bool, normalizedPath: Bool) -> String {
        let trimmed = rawURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseStrategy: String
        if let absoluteURL = URL(string: trimmed),
           absoluteURL.scheme != nil {
            baseStrategy = "absoluteRawURL"
        } else {
            baseStrategy = "originPlusRawPathAndQuery"
        }

        var strategy = copiedQuery ? "\(baseStrategy)+queryCopiedFromStreamURL" : baseStrategy
        if normalizedPath {
            strategy += "+addV1PrefixForHLS"
        }
        return strategy
    }
}

enum HLSStreamPathNormalizationAction: String, Sendable {
    case addV1PrefixForHLS
    case alreadyV1HLSPath
    case notHLSStreamPath
}

struct HLSStreamPathNormalization: Equatable, Sendable {
    let originalPath: String
    let normalizedPath: String
    let action: HLSStreamPathNormalizationAction

    var didChange: Bool {
        originalPath != normalizedPath
    }
}

enum HLSStreamPathNormalizer {
    static func normalizeHLSStreamPath(_ path: String) -> String {
        normalization(for: path).normalizedPath
    }

    static func normalization(for path: String) -> HLSStreamPathNormalization {
        if path.hasPrefix("/v1/videos/stream/") {
            return HLSStreamPathNormalization(
                originalPath: path,
                normalizedPath: path,
                action: .alreadyV1HLSPath
            )
        }

        if path.hasPrefix("/videos/stream/") {
            return HLSStreamPathNormalization(
                originalPath: path,
                normalizedPath: "/v1\(path)",
                action: .addV1PrefixForHLS
            )
        }

        return HLSStreamPathNormalization(
            originalPath: path,
            normalizedPath: path,
            action: .notHLSStreamPath
        )
    }

    static func normalize(url: URL) -> (url: URL, normalization: HLSStreamPathNormalization) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            let normalization = normalization(for: url.path)
            return (url, normalization)
        }

        let normalization = normalization(for: components.percentEncodedPath)
        guard normalization.didChange else {
            return (url, normalization)
        }

        components.percentEncodedPath = normalization.normalizedPath
        components.percentEncodedQuery = rawQuery(from: url.absoluteString)
        return (components.url ?? url, normalization)
    }

    private static func rawQuery(from value: String) -> String? {
        guard let questionMarkIndex = value.firstIndex(of: "?") else {
            return nil
        }

        let queryStart = value.index(after: questionMarkIndex)
        if let fragmentIndex = value[queryStart...].firstIndex(of: "#") {
            return String(value[queryStart..<fragmentIndex])
        }
        return String(value[queryStart...])
    }
}

private extension String {
    var pikkoSanitizedDisplayText: String {
        let scalars = unicodeScalars.map { scalar -> UnicodeScalar in
            if scalar.value == 0xFFFD || scalar.value == 0xFFFC {
                return UnicodeScalar(0x20)!
            }

            if CharacterSet.controlCharacters.contains(scalar),
               scalar.value != 0x0A,
               scalar.value != 0x09 {
                return UnicodeScalar(0x20)!
            }

            return scalar
        }

        return String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
