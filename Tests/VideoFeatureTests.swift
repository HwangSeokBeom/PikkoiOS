import XCTest
@testable import Pikko

final class VideoFeatureTests: XCTestCase {
    func testVideoResponseDTODecodesSwaggerSnakeCaseFields() throws {
        let dto = try NetworkCoding.makeJSONDecoder().decode(
            VideoResponseDTO.self,
            from: """
            {
              "video_id": "507f1f77bcf86cd799439011",
              "file_name": "video-name",
              "title": "안녕하세요 :)",
              "description": "같이 공부해요!! 아자아자!!",
              "duration": 120.5,
              "thumbnail_url": "/data/videos/video-name.jpg",
              "available_qualities": ["1080p", "720p", "480p"],
              "view_count": 1234,
              "like_count": 42,
              "is_liked": true,
              "createdAt": "2024-01-15T10:30:00.000Z"
            }
            """.data(using: .utf8)!
        )

        XCTAssertEqual(dto.videoId, "507f1f77bcf86cd799439011")
        XCTAssertEqual(dto.fileName, "video-name")
        XCTAssertEqual(dto.thumbnailURLPath, "/data/videos/video-name.jpg")
        XCTAssertEqual(dto.availableQualities, ["1080p", "720p", "480p"])
        XCTAssertEqual(dto.viewCount, 1234)
        XCTAssertEqual(dto.likeCount, 42)
        XCTAssertTrue(dto.isLiked)
    }

    func testVideoResponseDTONormalizesIdentifierCandidatesByPriority() throws {
        let decoder = NetworkCoding.makeJSONDecoder()

        let videoIdDTO = try decoder.decode(
            VideoResponseDTO.self,
            from: #"{"video_id":" video-snake ","videoId":"video-camel","id":"video-id","_id":"video-underscore","title":"A"}"#.data(using: .utf8)!
        )
        let camelDTO = try decoder.decode(
            VideoResponseDTO.self,
            from: #"{"videoId":"video-camel","id":"video-id","_id":"video-underscore","title":"A"}"#.data(using: .utf8)!
        )
        let idDTO = try decoder.decode(
            VideoResponseDTO.self,
            from: #"{"id":"video-id","_id":"video-underscore","title":"A"}"#.data(using: .utf8)!
        )
        let underscoreDTO = try decoder.decode(
            VideoResponseDTO.self,
            from: #"{"_id":"video-underscore","title":"A"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(videoIdDTO.videoId, "video-snake")
        XCTAssertEqual(camelDTO.videoId, "video-camel")
        XCTAssertEqual(idDTO.videoId, "video-id")
        XCTAssertEqual(underscoreDTO.videoId, "video-underscore")
    }

    func testVideoListResponseDecodesOptionalNextCursor() throws {
        let response = try NetworkCoding.makeJSONDecoder().decode(
            VideoListResponseDTO.self,
            from: """
            {
              "data": [],
              "next_cursor": "507f1f77bcf86cd799439010"
            }
            """.data(using: .utf8)!
        )

        XCTAssertEqual(response.data.count, 0)
        XCTAssertEqual(response.nextCursor, "507f1f77bcf86cd799439010")
    }

    func testVideoListResponseDecodesRootArrayAndTerminalCursors() throws {
        let rootArray = try NetworkCoding.makeJSONDecoder().decode(
            VideoListResponseDTO.self,
            from: """
            [
              { "video_id": "video-1", "title": "A" }
            ]
            """.data(using: .utf8)!
        )
        let emptyCursor = try NetworkCoding.makeJSONDecoder().decode(
            VideoListResponseDTO.self,
            from: #"{"data":[],"next_cursor":""}"#.data(using: .utf8)!
        )
        let zeroCursor = try NetworkCoding.makeJSONDecoder().decode(
            VideoListResponseDTO.self,
            from: #"{"data":[],"next_cursor":"0"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(rootArray.data.first?.videoId, "video-1")
        XCTAssertNil(rootArray.nextCursor)
        XCTAssertNil(emptyCursor.nextCursor)
        XCTAssertNil(zeroCursor.nextCursor)
    }

    func testVideoResponseDTOAllowsMissingOptionalFields() throws {
        let dto = try NetworkCoding.makeJSONDecoder().decode(
            VideoResponseDTO.self,
            from: #"{"video_id":"video-1","title":"A"}"#.data(using: .utf8)!
        )

        XCTAssertEqual(dto.videoId, "video-1")
        XCTAssertEqual(dto.fileName, "video-1")
        XCTAssertEqual(dto.description, "")
        XCTAssertEqual(dto.duration, 0)
        XCTAssertEqual(dto.availableQualities, [])
        XCTAssertFalse(dto.isLiked)
    }

    func testStreamUrlResponseDecodesQualitiesAndSubtitles() throws {
        let response = try NetworkCoding.makeJSONDecoder().decode(
            StreamUrlResponseDTO.self,
            from: """
            {
              "video_id": "video-1",
              "stream_url": "/videos/stream/video-name/master.m3u8?token=abc",
              "qualities": [
                { "quality": "1080p", "url": "/videos/stream/video-name/1080p/index.m3u8?token=abc" }
              ],
              "subtitles": [
                { "language": "ko", "name": "한국어", "is_default": true, "url": "/videos/stream/video-name/subtitles/ko" }
              ]
            }
            """.data(using: .utf8)!
        )

        XCTAssertEqual(response.videoId, "video-1")
        XCTAssertEqual(response.streamURLPath, "/videos/stream/video-name/master.m3u8?token=abc")
        XCTAssertEqual(response.qualities.first?.quality, "1080p")
        XCTAssertEqual(response.qualities.first?.urlPath, "/videos/stream/video-name/1080p/index.m3u8?token=abc")
        XCTAssertEqual(response.subtitles.first?.language, "ko")
        XCTAssertEqual(response.subtitles.first?.isDefault, true)
    }

    func testStreamUrlResponseDecodesOptionalSubtitleContractFields() throws {
        let response = try NetworkCoding.makeJSONDecoder().decode(
            StreamUrlResponseDTO.self,
            from: """
            {
              "video_id": "video-1",
              "stream_url": "/videos/stream/video-name/master.m3u8?token=abc",
              "subtitles": [
                {
                  "language_code": "en",
                  "display_name": "English",
                  "isDefault": true,
                  "format": "vtt",
                  "url": "https://example.com/en.vtt?token=subtitle-token"
                }
              ]
            }
            """.data(using: .utf8)!
        )

        XCTAssertEqual(response.subtitles.first?.language, "en")
        XCTAssertEqual(response.subtitles.first?.name, "English")
        XCTAssertEqual(response.subtitles.first?.format, "vtt")
        XCTAssertEqual(response.subtitles.first?.urlPath, "https://example.com/en.vtt?token=subtitle-token")
    }

    func testVideoSubtitleParserMatchesWebVTTCues() throws {
        let cues = VideoSubtitleParser.parse(
            """
            WEBVTT

            00:00:01.000 --> 00:00:02.500
            첫 번째 자막

            00:00:03.000 --> 00:00:04.000
            두 번째
            자막
            """,
            format: .webVTT
        )

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0], VideoSubtitleCue(start: 1, end: 2.5, text: "첫 번째 자막"))
        XCTAssertEqual(cues[1], VideoSubtitleCue(start: 3, end: 4, text: "두 번째\n자막"))
    }

    func testVideoSubtitleParserMatchesSRTCues() throws {
        let cues = VideoSubtitleParser.parse(
            """
            1
            00:00:01,000 --> 00:00:02,000
            안녕하세요
            """,
            format: .srt
        )

        XCTAssertEqual(cues, [
            VideoSubtitleCue(start: 1, end: 2, text: "안녕하세요")
        ])
    }

    func testVideoLikeRequestEncodesLikeStatusKey() throws {
        let data = try NetworkCoding.makeJSONEncoder().encode(VideoLikeRequestDTO(likeStatus: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Bool])

        XCTAssertEqual(object["like_status"], true)
        XCTAssertNil(object["likeStatus"])
    }

    func testVideoMapperResolvesAbsoluteURLsWithoutLosingTokenQuery() throws {
        let mapper = makeMapper()

        let video = mapper.map(
            VideoResponseDTO(
                videoId: "video-1",
                fileName: "a",
                title: "A",
                description: "B",
                duration: 65,
                thumbnailURLPath: "/data/videos/a.jpg",
                availableQualities: [],
                viewCount: 0,
                likeCount: 0,
                isLiked: false,
                createdAt: "2024-01-15T10:30:00.000Z"
            )
        )

        let stream = try mapper.map(
            StreamUrlResponseDTO(
                videoId: "video-1",
                streamURLPath: "/videos/stream/a/master.m3u8?token=abc",
                qualities: [
                    VideoStreamQualityDTO(quality: "720p", urlPath: "videos/stream/a/720p/index.m3u8?token=abc")
                ],
                subtitles: [
                    VideoSubtitleDTO(language: "ko", name: "한국어", isDefault: true, urlPath: "https://example.com/subtitle.vtt")
                ]
            )
        )

        XCTAssertEqual(video.thumbnailURL, "http://pickup.sesac.kr:42678/v1/data/videos/a.jpg")
        XCTAssertEqual(stream.streamURL.absoluteString, "http://pickup.sesac.kr:42678/v1/videos/stream/a/master.m3u8?token=abc")
        XCTAssertEqual(stream.qualities.first?.url.absoluteString, "http://pickup.sesac.kr:42678/v1/videos/stream/a/720p/index.m3u8?token=abc")
        XCTAssertEqual(stream.subtitles.first?.url.absoluteString, "https://example.com/subtitle.vtt")
    }

    func testVideoMapperPreservesEncodedTokenQuery() throws {
        let mapper = makeMapper()
        let stream = try mapper.map(
            StreamUrlResponseDTO(
                videoId: "video-1",
                streamURLPath: "/videos/stream/a/master.m3u8?token=abc+def%2Fghi%3D&expires=123",
                qualities: [
                    VideoStreamQualityDTO(
                        quality: "480p",
                        urlPath: "/videos/stream/a/480p/index.m3u8?token=abc+def%2Fghi%3D&expires=123"
                    )
                ],
                subtitles: []
            )
        )

        XCTAssertEqual(
            stream.streamURL.absoluteString,
            "http://pickup.sesac.kr:42678/v1/videos/stream/a/master.m3u8?token=abc+def%2Fghi%3D&expires=123"
        )
        XCTAssertEqual(
            stream.qualities.first?.url.absoluteString,
            "http://pickup.sesac.kr:42678/v1/videos/stream/a/480p/index.m3u8?token=abc+def%2Fghi%3D&expires=123"
        )
    }

    func testVideoMapperCopiesStreamTokenQueryToQualityURLWhenMissing() throws {
        let mapper = makeMapper()
        let stream = try mapper.map(
            StreamUrlResponseDTO(
                videoId: "video-1",
                streamURLPath: "/videos/stream/a/master.m3u8?token=abc+def%2Fghi%3D&expires=123",
                qualities: [
                    VideoStreamQualityDTO(
                        quality: "720p",
                        urlPath: "/videos/stream/a/720p/index.m3u8"
                    )
                ],
                subtitles: []
            )
        )

        XCTAssertEqual(
            stream.qualities.first?.url.absoluteString,
            "http://pickup.sesac.kr:42678/v1/videos/stream/a/720p/index.m3u8?token=abc+def%2Fghi%3D&expires=123"
        )
    }

    func testHLSStreamPathNormalizerAddsV1PrefixOnlyForHLSStreamPaths() {
        XCTAssertEqual(
            HLSStreamPathNormalizer.normalizeHLSStreamPath("/videos/stream/pickup_video_5/master.m3u8"),
            "/v1/videos/stream/pickup_video_5/master.m3u8"
        )
        XCTAssertEqual(
            HLSStreamPathNormalizer.normalizeHLSStreamPath("/videos/stream/pickup_video_5/1080p/index.m3u8"),
            "/v1/videos/stream/pickup_video_5/1080p/index.m3u8"
        )
        XCTAssertEqual(
            HLSStreamPathNormalizer.normalizeHLSStreamPath("/videos/stream/pickup_video_5/720p/index.m3u8"),
            "/v1/videos/stream/pickup_video_5/720p/index.m3u8"
        )
        XCTAssertEqual(
            HLSStreamPathNormalizer.normalizeHLSStreamPath("/videos/stream/pickup_video_5/480p/index.m3u8"),
            "/v1/videos/stream/pickup_video_5/480p/index.m3u8"
        )
        XCTAssertEqual(
            HLSStreamPathNormalizer.normalizeHLSStreamPath("/v1/videos/stream/pickup_video_5/master.m3u8"),
            "/v1/videos/stream/pickup_video_5/master.m3u8"
        )
        XCTAssertEqual(
            HLSStreamPathNormalizer.normalizeHLSStreamPath("/v1/data/videos/pickup_video_5.jpg"),
            "/v1/data/videos/pickup_video_5.jpg"
        )
        XCTAssertEqual(
            HLSStreamPathNormalizer.normalizeHLSStreamPath("/stores/abc"),
            "/stores/abc"
        )
    }

    func testHLSStreamURLNormalizerPreservesHostPortAndRawTokenQuery() throws {
        let url = try XCTUnwrap(URL(string: "http://pickup.sesac.kr:42678/videos/stream/pickup_video_5/master.m3u8?token=abc+def%2Fghi%3D&expires=123"))
        let result = HLSStreamPathNormalizer.normalize(url: url)

        XCTAssertEqual(result.url.scheme, "http")
        XCTAssertEqual(result.url.host, "pickup.sesac.kr")
        XCTAssertEqual(result.url.port, 42678)
        XCTAssertEqual(
            result.url.absoluteString,
            "http://pickup.sesac.kr:42678/v1/videos/stream/pickup_video_5/master.m3u8?token=abc+def%2Fghi%3D&expires=123"
        )
        XCTAssertEqual(result.normalization.action, .addV1PrefixForHLS)
    }

    func testVideoMapperDoesNotNormalizeNonHLSPaths() throws {
        let mapper = makeMapper()
        let video = mapper.map(
            VideoResponseDTO(
                videoId: "video-1",
                fileName: "a",
                title: "A",
                description: "B",
                duration: 65,
                thumbnailURLPath: "/data/videos/pickup_video_5.jpg",
                availableQualities: [],
                viewCount: 0,
                likeCount: 0,
                isLiked: false,
                createdAt: "2024-01-15T10:30:00.000Z"
            )
        )

        XCTAssertEqual(video.thumbnailURL, "http://pickup.sesac.kr:42678/v1/data/videos/pickup_video_5.jpg")
    }

    func testVideoMapperDropsEmptyAndDuplicateIDs() throws {
        let mapper = makeMapper()
        let page = mapper.mapPage(
            VideoListResponseDTO(
                data: [
                    VideoResponseDTO(
                        videoId: "video-1",
                        fileName: "a",
                        title: "A",
                        description: "",
                        duration: 0,
                        thumbnailURLPath: "",
                        availableQualities: [],
                        viewCount: 0,
                        likeCount: 0,
                        isLiked: false,
                        createdAt: ""
                    ),
                    VideoResponseDTO(
                        videoId: "",
                        fileName: "b",
                        title: "B",
                        description: "",
                        duration: 0,
                        thumbnailURLPath: "",
                        availableQualities: [],
                        viewCount: 0,
                        likeCount: 0,
                        isLiked: false,
                        createdAt: ""
                    ),
                    VideoResponseDTO(
                        videoId: "video-1",
                        fileName: "c",
                        title: "C",
                        description: "",
                        duration: 0,
                        thumbnailURLPath: "",
                        availableQualities: [],
                        viewCount: 0,
                        likeCount: 0,
                        isLiked: false,
                        createdAt: ""
                    )
                ],
                nextCursor: nil
            )
        )

        XCTAssertEqual(page.items.map(\.videoId), ["video-1"])
    }

    func testVideoRemoteDataSourceRejectsEmptyStreamVideoIDBeforeRequest() async throws {
        let apiClient = RecordingVideoAPIClient(
            response: StreamUrlResponseDTO(
                videoId: "video-1",
                streamURLPath: "/videos/stream/a/master.m3u8",
                qualities: [],
                subtitles: []
            )
        )
        let dataSource = VideoRemoteDataSource(apiClient: apiClient)

        do {
            _ = try await dataSource.fetchVideoStream(videoId: " ")
            XCTFail("Expected invalid video id")
        } catch let error as VideoStreamRequestError {
            XCTAssertEqual(error, .invalidVideoId)
        }

        XCTAssertNil(apiClient.recordedPath)
    }

    func testDurationFormatterUsesFloorSeconds() {
        XCTAssertEqual(VideoDurationFormatter.string(from: 120.5), "02:00")
        XCTAssertEqual(VideoDurationFormatter.string(from: 65), "01:05")
    }

    func testVideoOptimisticLikeUpdateAndRollbackModel() {
        let video = makeVideo(isLiked: false, likeCount: 2)
        let liked = video.updatingLikeStatus(true)
        let rolledBack = liked.updatingLikeStatus(false)

        XCTAssertTrue(liked.isLiked)
        XCTAssertEqual(liked.likeCount, 3)
        XCTAssertFalse(rolledBack.isLiked)
        XCTAssertEqual(rolledBack.likeCount, 2)

        let unliked = makeVideo(isLiked: true, likeCount: 1).updatingLikeStatus(false)
        XCTAssertFalse(unliked.isLiked)
        XCTAssertEqual(unliked.likeCount, 0)
    }

    private func makeMapper() -> VideoMapper {
        VideoMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )
    }

    private func makeVideo(isLiked: Bool, likeCount: Int) -> Video {
        Video(
            videoId: "video-1",
            fileName: "a",
            title: "A",
            description: "B",
            duration: 65,
            thumbnailURL: nil,
            availableQualities: ["720p"],
            viewCount: 10,
            likeCount: likeCount,
            isLiked: isLiked,
            createdAt: nil
        )
    }
}

@MainActor
final class VideoListPresenterTests: XCTestCase {
    func testVideoTabAppearCallsListAPIAndShowsLoadedState() async {
        let interactor = StubVideoListInteractor(
            pages: [CursorPage(items: [makeVideo()], nextCursor: nil)]
        )
        let presenter = VideoListPresenter(interactor: interactor, router: SpyVideoListRouter())

        await presenter.send(.onAppear)

        XCTAssertEqual(interactor.loadVideosCallCount, 1)
        XCTAssertEqual(interactor.lastLimit, 20)
        XCTAssertEqual(presenter.viewState.videos.map(\.id), ["video-1"])
        XCTAssertFalse(presenter.viewState.isLoading)
        XCTAssertNil(presenter.viewState.errorMessage)
    }

    func testVideoListFailureShowsErrorState() async {
        let presenter = VideoListPresenter(
            interactor: StubVideoListInteractor(error: NetworkError.transport),
            router: SpyVideoListRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.showsErrorState)
        XCTAssertEqual(presenter.viewState.errorMessage, "영상을 불러오지 못했어요.")
    }

    func testVideoListEmptyResponseShowsEmptyState() async {
        let presenter = VideoListPresenter(
            interactor: StubVideoListInteractor(pages: [CursorPage(items: [], nextCursor: nil)]),
            router: SpyVideoListRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.showsEmptyState)
        XCTAssertTrue(presenter.viewState.videos.isEmpty)
    }

    func testVideoLikeOptimisticUpdateSuccess() async {
        let interactor = StubVideoListInteractor(
            pages: [CursorPage(items: [makeVideo(isLiked: false, likeCount: 2)], nextCursor: nil)],
            likeResult: true
        )
        let presenter = VideoListPresenter(interactor: interactor, router: SpyVideoListRouter())

        await presenter.send(.onAppear)
        await presenter.send(.videoLikeTapped("video-1"))

        XCTAssertEqual(interactor.updateLikeCallCount, 1)
        XCTAssertTrue(presenter.viewState.videos[0].isLiked)
        XCTAssertEqual(presenter.viewState.videos[0].likeCountText, "3")
    }

    func testVideoLikeOptimisticUpdateRollsBackOnFailure() async {
        let presenter = VideoListPresenter(
            interactor: StubVideoListInteractor(
                pages: [CursorPage(items: [makeVideo(isLiked: false, likeCount: 2)], nextCursor: nil)],
                likeError: NetworkError.transport
            ),
            router: SpyVideoListRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.videoLikeTapped("video-1"))

        XCTAssertFalse(presenter.viewState.videos[0].isLiked)
        XCTAssertEqual(presenter.viewState.videos[0].likeCountText, "2")
    }

    func testVideoTapRoutesToPlayer() async {
        let router = SpyVideoListRouter()
        let presenter = VideoListPresenter(
            interactor: StubVideoListInteractor(pages: [CursorPage(items: [makeVideo()], nextCursor: nil)]),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.videoTapped("video-1"))

        XCTAssertEqual(router.routedVideo?.videoId, "video-1")
    }

    func testVideoTapWithEmptyIDDoesNotRouteToPlayer() async {
        let router = SpyVideoListRouter()
        let presenter = VideoListPresenter(
            interactor: StubVideoListInteractor(pages: [CursorPage(items: [makeVideo(videoId: "")], nextCursor: nil)]),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.videoTapped(""))

        XCTAssertNil(router.routedVideo)
        XCTAssertTrue(presenter.viewState.videos.isEmpty)
    }
}

@MainActor
final class VideoPlayerTests: XCTestCase {
    func testPlayerEntryRequestsStreamOnce() async {
        let repository = StubVideoRepository(stream: makeStream())
        let viewModel = VideoPlayerViewModel(
            video: makeVideo(),
            fetchStreamUseCase: FetchVideoStreamUseCase(repository: repository),
            setLikeUseCase: SetVideoLikeUseCase(repository: repository)
        )

        await viewModel.loadStreamIfNeeded()
        await viewModel.loadStreamIfNeeded()

        XCTAssertEqual(repository.fetchStreamCallCount, 1)
        XCTAssertEqual(viewModel.viewState.stream?.videoId, "video-1")
    }

    func testPlayerRetryRequestsStreamAgain() async {
        let repository = StubVideoRepository(stream: makeStream())
        let viewModel = VideoPlayerViewModel(
            video: makeVideo(),
            fetchStreamUseCase: FetchVideoStreamUseCase(repository: repository),
            setLikeUseCase: SetVideoLikeUseCase(repository: repository)
        )

        await viewModel.loadStreamIfNeeded()
        await viewModel.retryStream()

        XCTAssertEqual(repository.fetchStreamCallCount, 2)
    }

    func testPlayerStreamStateDoesNotExposeMaskedLogMaterial() async {
        let streamURL = URL(string: "https://example.com/master.m3u8?token=abc")!
        let repository = StubVideoRepository(stream: makeStream(streamURL: streamURL))
        let viewModel = VideoPlayerViewModel(
            video: makeVideo(),
            fetchStreamUseCase: FetchVideoStreamUseCase(repository: repository),
            setLikeUseCase: SetVideoLikeUseCase(repository: repository)
        )

        await viewModel.loadStreamIfNeeded()

        XCTAssertEqual(viewModel.viewState.stream?.streamURL, streamURL)
        XCTAssertEqual(repository.fetchStreamCallCount, 1)
    }

    func testPlayerRejectsEmptyVideoIDWithoutRequestingStream() async {
        let repository = StubVideoRepository(stream: makeStream())
        let viewModel = VideoPlayerViewModel(
            video: makeVideo(videoId: ""),
            fetchStreamUseCase: FetchVideoStreamUseCase(repository: repository),
            setLikeUseCase: SetVideoLikeUseCase(repository: repository)
        )

        await viewModel.loadStreamIfNeeded()

        XCTAssertEqual(repository.fetchStreamCallCount, 0)
        XCTAssertEqual(viewModel.viewState.playbackState, .failed("영상 정보를 불러올 수 없어요."))
    }

    func testPlayerForbiddenStreamShowsErrorWithoutAuthenticationState() async {
        let repository = StubVideoRepository(stream: makeStream(), streamError: NetworkError.forbidden)
        let viewModel = VideoPlayerViewModel(
            video: makeVideo(),
            fetchStreamUseCase: FetchVideoStreamUseCase(repository: repository),
            setLikeUseCase: SetVideoLikeUseCase(repository: repository)
        )

        await viewModel.loadStreamIfNeeded()

        XCTAssertEqual(repository.fetchStreamCallCount, 1)
        XCTAssertEqual(viewModel.viewState.playbackState, .failed("이 영상을 재생할 수 없어요."))
    }
}

@MainActor
private final class StubVideoListInteractor: VideoListInteracting {
    private(set) var loadVideosCallCount = 0
    private(set) var updateLikeCallCount = 0
    private(set) var lastLimit: Int?
    private(set) var lastNextCursor: String?

    private var pages: [CursorPage<Video>]
    private let error: Error?
    private let likeResult: Bool
    private let likeError: Error?

    init(
        pages: [CursorPage<Video>] = [],
        error: Error? = nil,
        likeResult: Bool = true,
        likeError: Error? = nil
    ) {
        self.pages = pages
        self.error = error
        self.likeResult = likeResult
        self.likeError = likeError
    }

    func loadVideos(nextCursor: String?, limit: Int) async throws -> CursorPage<Video> {
        loadVideosCallCount += 1
        lastNextCursor = nextCursor
        lastLimit = limit
        if let error {
            throw error
        }
        return pages.isEmpty ? CursorPage(items: [], nextCursor: nil) : pages.removeFirst()
    }

    func updateVideoLikeStatus(videoID: String, isLiked: Bool) async throws -> Bool {
        _ = videoID
        _ = isLiked
        updateLikeCallCount += 1
        if let likeError {
            throw likeError
        }
        return likeResult
    }
}

@MainActor
private final class SpyVideoListRouter: VideoListRouting {
    private(set) var routedVideo: Video?

    func routeToVideoPlayer(video: Video) {
        routedVideo = video
    }

    func clearPendingRoute() {
        routedVideo = nil
    }
}

private final class StubVideoRepository: VideoRepository, @unchecked Sendable {
    private(set) var fetchStreamCallCount = 0
    private let stream: VideoStream
    private let streamError: Error?

    init(stream: VideoStream, streamError: Error? = nil) {
        self.stream = stream
        self.streamError = streamError
    }

    func fetchVideos(nextCursor: String?, limit: Int) async throws -> CursorPage<Video> {
        _ = nextCursor
        _ = limit
        return CursorPage(items: [], nextCursor: nil)
    }

    func fetchVideoStream(videoId: String) async throws -> VideoStream {
        _ = videoId
        fetchStreamCallCount += 1
        if let streamError {
            throw streamError
        }
        return stream
    }

    func updateLikeStatus(videoId: String, isLiked: Bool) async throws -> Bool {
        _ = videoId
        return isLiked
    }
}

private final class RecordingVideoAPIClient: APIClientProtocol, @unchecked Sendable {
    let response: Any
    private(set) var recordedPath: String?

    init(response: Any) {
        self.response = response
    }

    func execute<ResponseDTO>(_ endpoint: Endpoint<ResponseDTO>) async throws -> ResponseDTO where ResponseDTO: Decodable, ResponseDTO: Sendable {
        recordedPath = endpoint.path
        if let response = response as? ResponseDTO {
            return response
        }

        throw NetworkError.decoding
    }
}

private func makeVideo(
    videoId: String = "video-1",
    isLiked: Bool = false,
    likeCount: Int = 2
) -> Video {
    Video(
        videoId: videoId,
        fileName: "a",
        title: "A",
        description: "B",
        duration: 65,
        thumbnailURL: nil,
        availableQualities: ["720p"],
        viewCount: 10,
        likeCount: likeCount,
        isLiked: isLiked,
        createdAt: nil
    )
}

private func makeStream(
    streamURL: URL = URL(string: "https://example.com/master.m3u8?token=abc")!
) -> VideoStream {
    VideoStream(
        videoId: "video-1",
        streamURL: streamURL,
        qualities: [
            VideoStreamQuality(quality: "720p", url: streamURL)
        ],
        subtitles: []
    )
}
