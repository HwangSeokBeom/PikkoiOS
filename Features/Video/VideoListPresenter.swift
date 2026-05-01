import Foundation

@MainActor
final class VideoListPresenter: ObservableObject {
    @Published private(set) var viewState: VideoListViewState

    private let interactor: VideoListInteracting
    private let router: VideoListRouting
    private let sessionStore: SessionStore?
    private let logger = Logger(category: "VideoList")
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()

    private var hasLoaded = false
    private var isPaging = false
    private var videos: [Video] = []
    private var updatingVideoLikeIDs = Set<String>()
    private let pageLimit = 20

    init(
        interactor: VideoListInteracting,
        router: VideoListRouting,
        sessionStore: SessionStore? = nil,
        initialState: VideoListViewState = VideoListViewState()
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
        self.viewState = initialState
    }

    func send(_ action: VideoListAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await reload(reason: "initial")
        case .refreshRequested:
            await reload(reason: "refresh")
        case .retryTapped:
            await reload(reason: "retry")
        case .videoAppeared(let videoID):
            await loadNextPageIfNeeded(triggeredBy: videoID)
        case .videoTapped(let videoID):
            let normalizedVideoID = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedVideoID.isEmpty else {
                logger.warning("[VideoList] blocked selection because videoId is empty title=unknown")
                viewState.errorMessage = "영상 정보를 불러올 수 없어요."
                return
            }

            guard let video = videos.first(where: { $0.videoId == normalizedVideoID }) else {
                logger.warning("[VideoList] blocked selection because video was not found videoId=\(normalizedVideoID)")
                viewState.errorMessage = "영상 정보를 불러올 수 없어요."
                return
            }

            logger.debug("[VideoList] select videoId=\(video.videoId) title=\(video.title)")
            router.routeToVideoPlayer(video: video)
        case .videoLikeTapped(let videoID):
            await toggleVideoLike(for: videoID)
        case .videoUpdated(let updatedVideo):
            applyUpdatedVideo(updatedVideo)
        }
    }

    private func reload(reason: String) async {
        guard sessionStore?.isAuthenticated != false else {
            applyUnavailableState(message: "로그인이 필요합니다. 다시 로그인해 주세요.")
            return
        }

        logger.debug("[VideoList] reload reason=\(reason)")
        if hasLoaded {
            viewState.isRefreshing = true
        } else {
            viewState.isLoading = true
        }
        viewState.errorMessage = nil

        do {
            let page = try await interactor.loadVideos(nextCursor: nil, limit: pageLimit)
            videos = sanitizedVideos(page.items)
            viewState.videos = videos.map(makeVideoCardModel)
            viewState.nextCursor = page.nextCursor
            viewState.errorMessage = nil
            hasLoaded = true
            logger.debug("[VideoList] loaded count=\(videos.count) nextCursor=\(page.nextCursor ?? "nil")")
        } catch {
            applyUnavailableState(message: "영상을 불러오지 못했어요.")
            logger.info("[VideoList] unavailable message=영상을 불러오지 못했어요.")
        }

        viewState.isLoading = false
        viewState.isRefreshing = false
    }

    private func loadNextPageIfNeeded(triggeredBy videoID: String) async {
        guard sessionStore?.isAuthenticated != false else {
            applyUnavailableState(message: "로그인이 필요합니다. 다시 로그인해 주세요.")
            return
        }

        guard !isPaging,
              let nextCursor = viewState.nextCursor,
              videoID == viewState.videos.last?.id else {
            return
        }

        isPaging = true
        viewState.isPaging = true
        defer {
            isPaging = false
            viewState.isPaging = false
        }

        do {
            let page = try await interactor.loadVideos(nextCursor: nextCursor, limit: pageLimit)
            videos = sanitizedVideos(videos + page.items)
            viewState.videos = videos.map(makeVideoCardModel)
            viewState.nextCursor = page.nextCursor
            logger.debug("[VideoList] loaded count=\(videos.count) nextCursor=\(page.nextCursor ?? "nil")")
        } catch {
            viewState.errorMessage = "영상을 불러오지 못했어요."
            logger.info("[VideoList] unavailable message=영상을 불러오지 못했어요.")
        }
    }

    private func toggleVideoLike(for videoID: String) async {
        guard sessionStore?.isAuthenticated != false else {
            applyUnavailableState(message: "로그인이 필요합니다. 다시 로그인해 주세요.")
            return
        }

        guard !updatingVideoLikeIDs.contains(videoID),
              let previousVideo = videos.first(where: { $0.videoId == videoID }) else {
            return
        }

        let previousVideos = videos
        let optimisticLikeStatus = !previousVideo.isLiked
        updatingVideoLikeIDs.insert(videoID)
        applyVideoLikeStatus(optimisticLikeStatus, to: videoID)

        do {
            let confirmedLikeStatus = try await interactor.updateVideoLikeStatus(
                videoID: videoID,
                isLiked: optimisticLikeStatus
            )
            applyVideoLikeStatus(confirmedLikeStatus, to: videoID)
        } catch {
            videos = previousVideos
            viewState.videos = videos.map(makeVideoCardModel)
            viewState.errorMessage = resolveErrorMessage(from: error)
        }

        updatingVideoLikeIDs.remove(videoID)
        viewState.videos = videos.map(makeVideoCardModel)
    }

    private func applyUnavailableState(message: String) {
        viewState.errorMessage = message
        viewState.isLoading = false
        viewState.isRefreshing = false
    }

    private func applyUpdatedVideo(_ updatedVideo: Video) {
        let normalizedVideoID = updatedVideo.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoID.isEmpty,
              videos.contains(where: { $0.videoId == normalizedVideoID }) else { return }
        videos = videos.map { video in
            video.videoId == normalizedVideoID ? updatedVideo : video
        }
        viewState.videos = videos.map(makeVideoCardModel)
    }

    private func applyVideoLikeStatus(_ isLiked: Bool, to videoID: String) {
        videos = videos.map { video in
            guard video.videoId == videoID else { return video }
            return video.updatingLikeStatus(isLiked)
        }
        viewState.videos = videos.map(makeVideoCardModel)
    }

    private func makeVideoCardModel(_ video: Video) -> VideoCardModel {
        VideoCardModel(
            id: video.videoId.trimmingCharacters(in: .whitespacesAndNewlines),
            title: video.title,
            description: video.description,
            thumbnailURL: video.thumbnailURL,
            durationText: VideoDurationFormatter.string(from: video.duration),
            viewCountText: countText(video.viewCount),
            likeCountText: countText(video.likeCount),
            isLiked: video.isLiked,
            qualityLabels: Array(video.availableQualities.prefix(3)),
            createdAtText: createdAtText(from: video.createdAt),
            isLikeUpdating: updatingVideoLikeIDs.contains(video.videoId)
        )
    }

    private func sanitizedVideos(_ candidates: [Video]) -> [Video] {
        var seenIDs = Set<String>()
        var sanitized: [Video] = []
        var droppedEmptyIDCount = 0
        var droppedDuplicateIDCount = 0

        for video in candidates {
            let videoID = video.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !videoID.isEmpty else {
                droppedEmptyIDCount += 1
                logger.warning("[VideoMapping] dropped video because id is empty title=\(video.title)")
                continue
            }

            guard seenIDs.insert(videoID).inserted else {
                droppedDuplicateIDCount += 1
                logger.warning("[VideoMapping] duplicated videoId dropped videoId=\(videoID)")
                continue
            }

            if videoID == video.videoId {
                sanitized.append(video)
            } else {
                sanitized.append(
                    Video(
                        videoId: videoID,
                        fileName: video.fileName,
                        title: video.title,
                        description: video.description,
                        duration: video.duration,
                        thumbnailURL: video.thumbnailURL,
                        availableQualities: video.availableQualities,
                        viewCount: video.viewCount,
                        likeCount: video.likeCount,
                        isLiked: video.isLiked,
                        createdAt: video.createdAt
                    )
                )
            }
        }

        logger.debug(
            "[VideoMapping] mapped count=\(sanitized.count) droppedEmptyId=\(droppedEmptyIDCount) droppedDuplicateId=\(droppedDuplicateIDCount)"
        )
        return sanitized
    }

    private func countText(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f만", Double(count) / 10_000)
        }

        if count >= 1_000 {
            return String(format: "%.1f천", Double(count) / 1_000)
        }

        return "\(count)"
    }

    private func createdAtText(from date: Date?) -> String {
        guard let date else { return "" }
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}
