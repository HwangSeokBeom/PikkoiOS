import Foundation

@MainActor
final class VideoListPresenter: ObservableObject {
    @Published private(set) var viewState: VideoListViewState

    private let interactor: VideoListInteracting
    private let router: VideoListRouting
    private let sessionStore: SessionStore?
    private let videoLiveActivityManager: VideoLiveActivityManaging
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
    private var reloadGeneration = 0
    private var pagingGeneration = 0
    private var shortsPlaybackSnapshotByVideoID: [String: VideoLiveActivitySnapshot] = [:]
    private var hasPerformedInitialAutoplayForCurrentEntry = false
    private var isVideoScreenVisible = false
    private let pageLimit = 20

    init(
        interactor: VideoListInteracting,
        router: VideoListRouting,
        sessionStore: SessionStore? = nil,
        videoLiveActivityManager: VideoLiveActivityManaging = NoopVideoLiveActivityService.shared,
        initialState: VideoListViewState = VideoListViewState()
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
        self.videoLiveActivityManager = videoLiveActivityManager
        self.viewState = initialState
    }

    func send(_ action: VideoListAction) async {
        switch action {
        case .onAppear:
            isVideoScreenVisible = true
            viewState.pendingDisappearReason = .tabSwitch
            if !hasPerformedInitialAutoplayForCurrentEntry {
                logger.debug("[VideoAutoplay] initial entry armed")
            }
            guard !hasLoaded else {
                attemptInitialAutoplayIfNeeded(reason: "appear")
                return
            }
            await reload(reason: "initial")
        case .refreshRequested:
            await reload(reason: "refresh")
        case .retryTapped:
            await reload(reason: "retry")
        case .videoAppeared(let videoID):
            await loadNextPageIfNeeded(triggeredBy: videoID)
        case .visibleVideoChanged(let videoID):
            let target = ShortsVisibleTarget(rawValue: videoID)
            if viewState.openingOriginalVideoID != nil {
                logger.debug("[ShortsVisibility] update ignored reason=openOriginalInProgress target=\(target.logValue)")
                return
            }
            guard case .video(let visibleVideoID) = target else {
                logger.debug("[ShortsVisibility] target=\(target.logValue) ignoredForPlayback=true")
                logger.debug("[ShortsPlayer] activeVideo unchanged reason=sentinelVisible")
                return
            }
            guard videos.contains(where: { $0.videoId == visibleVideoID }) else {
                logger.debug("[ShortsPlayer] invalidVideoId ignored value=\(visibleVideoID)")
                return
            }
            let previousActiveVideoID = viewState.activeShortsVideoID
            let nextState = ShortsPlayerStateReducer.visibleItemChanged(
                currentVideoID: viewState.activeShortsVideoID,
                isPlaying: viewState.isShortsPlaying,
                visibleVideoID: visibleVideoID
            )
            viewState.activeShortsVideoID = nextState.activeVideoID
            viewState.isShortsPlaying = nextState.isPlaying
            if previousActiveVideoID != nextState.activeVideoID {
                logger.debug("[ShortsPlayer] activeVideo changed from=\(previousActiveVideoID ?? "nil") to=\(nextState.activeVideoID ?? "nil") reason=visibleVideo")
            }
        case .videoTapped(let videoID):
            guard videos.contains(where: { $0.videoId == videoID }) else {
                logger.debug("[ShortsPlayer] invalidVideoId ignored value=\(videoID)")
                return
            }
            let nextState = ShortsPlayerStateReducer.togglePlayback(
                currentVideoID: viewState.activeShortsVideoID,
                isPlaying: viewState.isShortsPlaying,
                tappedVideoID: videoID
            )
            viewState.activeShortsVideoID = nextState.activeVideoID
            viewState.isShortsPlaying = nextState.isPlaying
            logger.debug("[ShortsVideo] tap action=togglePlayPause videoId=\(videoID) activeVideoId=\(nextState.activeVideoID ?? "nil") isPlaying=\(nextState.isPlaying)")
        case .originalVideoTapped(let videoID):
            let normalizedVideoID = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.debug("[ShortsOriginal] tap videoId=\(normalizedVideoID) shortsIndex=\(videos.firstIndex(where: { $0.videoId == normalizedVideoID }) ?? -1)")
            guard viewState.openingOriginalVideoID == nil else {
                logger.debug("[ShortsOriginal] open skipped reason=duplicateTap videoId=\(normalizedVideoID)")
                return
            }
            guard !normalizedVideoID.isEmpty else {
                logger.warning("[ShortsOriginal] open failed reason=missingVideoId")
                viewState.errorMessage = "영상 정보를 불러올 수 없어요."
                return
            }

            guard let video = videos.first(where: { $0.videoId == normalizedVideoID }) else {
                logger.warning("[ShortsOriginal] open failed reason=missingOriginalMetadata videoId=\(normalizedVideoID)")
                viewState.errorMessage = "영상 정보를 불러올 수 없어요."
                return
            }

            logger.debug("[ShortsOriginal] open requested videoId=\(video.videoId) source=shorts")
            logger.debug("[ShortsOriginal] transition state from=active to=openingOriginal videoId=\(video.videoId)")
            logger.debug("[ShortsOriginal] player policy=transferToDetail videoId=\(video.videoId)")
            logger.debug("[ShortsOriginal] freeze visibility updates videoId=\(video.videoId)")
            viewState.pendingDisappearReason = .openOriginal
            viewState.openingOriginalVideoID = video.videoId
            viewState.activeShortsVideoID = nil
            viewState.isShortsPlaying = false
            let didTransferPlayer = VideoPlaybackCoordinator.shared.transferToDetail(videoId: video.videoId)
            if didTransferPlayer {
                logger.debug("[ShortsOriginal] route append videoId=\(video.videoId) destination=videoDetail afterPlayerTransition=true")
            } else {
                logger.debug("[ShortsOriginal] route append videoId=\(video.videoId) destination=videoDetail afterPlayerTransition=false reason=noActivePlaybackSession")
            }
            router.routeToOriginalVideo(video: video)
        case .originalRouteCleared:
            viewState.openingOriginalVideoID = nil
            viewState.pendingDisappearReason = .tabSwitch
            if isVideoScreenVisible {
                hasPerformedInitialAutoplayForCurrentEntry = false
                attemptInitialAutoplayIfNeeded(reason: "originalRouteCleared")
            }
        case .videoLikeTapped(let videoID):
            await toggleVideoLike(for: videoID)
        case .videoUpdated(let updatedVideo):
            applyUpdatedVideo(updatedVideo)
        case .viewDisappeared(let reason):
            isVideoScreenVisible = false
            let activeVideoID = viewState.activeShortsVideoID
            if reason == .openOriginal {
                logger.debug("[ShortsPlayer] viewDisappear reason=openOriginal activeVideoId=\(activeVideoID ?? viewState.openingOriginalVideoID ?? "nil") cleanupMode=detachOnly")
                return
            }
            if reason == .appBackground {
                logger.debug("[VideoPlayback] continue reason=appBackgrounded videoId=\(activeVideoID ?? "nil")")
                return
            }
            if reason == .tabSwitch || reason == .pop || reason == .deinitializing {
                hasPerformedInitialAutoplayForCurrentEntry = false
            }
            if viewState.isShortsPlaying {
                viewState.isShortsPlaying = false
                logger.debug("[VideoPlayback] stop reason=\(reason.rawValue) videoId=\(activeVideoID ?? "nil")")
            } else {
                logger.debug("[VideoPlayback] stop skipped reason=alreadyStopped")
            }
        case .scenePhaseChanged(let isActive):
            if isActive {
                isVideoScreenVisible = true
                viewState.pendingDisappearReason = .tabSwitch
                logger.debug("[VideoPlayback] appWillEnterForeground restoreVisibleState videoId=\(viewState.activeShortsVideoID ?? "nil")")
                if let activeVideoID = viewState.activeShortsVideoID {
                    videoLiveActivityManager.end(videoId: activeVideoID, reason: .foreground)
                }
            } else {
                let activeVideoID = viewState.activeShortsVideoID
                let wasPlaying = viewState.isShortsPlaying
                viewState.pendingDisappearReason = .appBackground
                logger.debug("[VideoVisibility] event=appBackgrounded activeVideoId=\(activeVideoID ?? "nil")")
                videoLiveActivityManager.startOrUpdate(
                    snapshot: makeBackgroundLiveActivitySnapshot(activeVideoID: activeVideoID, wasPlaying: wasPlaying)
                )
                if wasPlaying, let activeVideoID {
                    logger.debug("[VideoPlayback] appDidEnterBackground keepPlaying=true videoId=\(activeVideoID)")
                    logger.debug("[VideoPlayback] continue reason=appBackgrounded videoId=\(activeVideoID)")
                    logger.debug("[LiveActivity] preserve reason=backgroundPlayback videoId=\(activeVideoID)")
                }
            }
        case .visibilityChanged(let isVisible, let reason):
            if isVisible {
                await send(.onAppear)
            } else {
                logger.debug("[VideoVisibility] event=\(reason.rawValue) activeVideoId=\(viewState.activeShortsVideoID ?? "nil")")
                await send(.viewDisappeared(reason: reason))
            }
        case .shortsPlaybackSnapshotUpdated(let snapshot):
            shortsPlaybackSnapshotByVideoID[snapshot.videoId] = snapshot
        }
    }

    private func reload(reason: String) async {
        guard sessionStore?.isAuthenticated != false else {
            applyUnavailableState(message: "로그인이 필요합니다. 다시 로그인해 주세요.")
            return
        }

        reloadGeneration += 1
        pagingGeneration += 1
        let generation = reloadGeneration
        logger.debug("[VideoList] reload reason=\(reason)")
        if hasLoaded {
            viewState.isRefreshing = true
        } else {
            viewState.isLoading = true
        }
        viewState.errorMessage = nil

        do {
            let page = try await interactor.loadVideos(nextCursor: nil, limit: pageLimit)
            guard generation == reloadGeneration else {
                logger.debug("[VideoList] stale reload ignored generation=\(generation) current=\(reloadGeneration)")
                return
            }
            videos = sanitizedVideos(page.items)
            viewState.videos = videos.map(makeVideoCardModel)
            if let activeVideoID = viewState.activeShortsVideoID,
               !videos.contains(where: { $0.videoId == activeVideoID }) {
                logger.debug("[ShortsPlayer] activeVideoId changed from=\(activeVideoID) to=nil reason=reload")
                viewState.activeShortsVideoID = nil
                viewState.isShortsPlaying = false
            }
            viewState.nextCursor = page.nextCursor
            viewState.errorMessage = nil
            hasLoaded = true
            logger.debug("[VideoList] loaded count=\(videos.count) nextCursor=\(page.nextCursor ?? "nil")")
            attemptInitialAutoplayIfNeeded(reason: "listLoaded")
        } catch {
            guard generation == reloadGeneration else {
                logger.debug("[VideoList] stale reload failure ignored generation=\(generation) current=\(reloadGeneration)")
                return
            }
            applyUnavailableState(message: "영상을 불러오지 못했어요.")
            logger.info("[VideoList] unavailable message=영상을 불러오지 못했어요.")
        }

        if generation == reloadGeneration {
            viewState.isLoading = false
            viewState.isRefreshing = false
        }
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
        pagingGeneration += 1
        let pageGeneration = pagingGeneration
        let reloadSnapshot = reloadGeneration
        viewState.isPaging = true
        defer {
            if pageGeneration == pagingGeneration {
                isPaging = false
                viewState.isPaging = false
            }
        }

        do {
            let page = try await interactor.loadVideos(nextCursor: nextCursor, limit: pageLimit)
            guard pageGeneration == pagingGeneration,
                  reloadSnapshot == reloadGeneration else {
                logger.debug("[VideoList] stale page ignored pageGeneration=\(pageGeneration) currentPage=\(pagingGeneration) reload=\(reloadSnapshot) currentReload=\(reloadGeneration)")
                return
            }
            videos = sanitizedVideos(videos + page.items)
            viewState.videos = videos.map(makeVideoCardModel)
            viewState.nextCursor = page.nextCursor
            logger.debug("[VideoList] loaded count=\(videos.count) nextCursor=\(page.nextCursor ?? "nil")")
        } catch {
            guard pageGeneration == pagingGeneration,
                  reloadSnapshot == reloadGeneration else {
                logger.debug("[VideoList] stale page failure ignored pageGeneration=\(pageGeneration) currentPage=\(pagingGeneration)")
                return
            }
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

    private func makeBackgroundLiveActivitySnapshot(activeVideoID: String?, wasPlaying: Bool) -> VideoLiveActivitySnapshot? {
        guard let activeVideoID,
              let video = videos.first(where: { $0.videoId == activeVideoID }) else {
            return nil
        }

        var snapshot = shortsPlaybackSnapshotByVideoID[activeVideoID] ?? VideoLiveActivitySnapshot(
            videoId: video.videoId,
            title: video.title,
            thumbnailURLString: video.thumbnailURL,
            playbackState: .paused,
            elapsedTime: 0,
            duration: video.duration,
            quality: video.availableQualities.first ?? "auto"
        )

        snapshot = VideoLiveActivitySnapshot(
            videoId: snapshot.videoId,
            title: snapshot.title,
            thumbnailURLString: snapshot.thumbnailURLString,
            playbackState: wasPlaying ? .playing : .paused,
            elapsedTime: snapshot.elapsedTime,
            duration: snapshot.duration > 0 ? snapshot.duration : video.duration,
            quality: snapshot.quality
        )
        return snapshot
    }

    private func applyUnavailableState(message: String) {
        viewState.errorMessage = message
        viewState.isLoading = false
        viewState.isRefreshing = false
    }

    private func attemptInitialAutoplayIfNeeded(reason: String) {
        guard !hasPerformedInitialAutoplayForCurrentEntry else { return }
        guard isVideoScreenVisible else {
            logger.debug("[VideoAutoplay] skipped reason=viewNotVisible")
            return
        }
        guard let firstVideo = videos.first else {
            logger.debug("[VideoAutoplay] skipped reason=listEmpty")
            return
        }

        hasPerformedInitialAutoplayForCurrentEntry = true
        viewState.activeShortsVideoID = firstVideo.videoId
        viewState.isShortsPlaying = true
        logger.debug("[VideoAutoplay] selected first videoId=\(firstVideo.videoId)")
        logger.debug("[VideoPlayback] state from=ready to=playing videoId=\(firstVideo.videoId) reason=initialAutoplay")
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
            video: video,
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

enum ShortsVisibleTarget: Equatable {
    case topSentinel
    case video(id: String)
    case bottomSentinel
    case invalid(String)

    init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "video-scroll-top":
            self = .topSentinel
        case "video-scroll-bottom":
            self = .bottomSentinel
        case "":
            self = .invalid(rawValue)
        default:
            self = .video(id: normalized)
        }
    }

    var logValue: String {
        switch self {
        case .topSentinel:
            return "topSentinel"
        case .bottomSentinel:
            return "bottomSentinel"
        case .video(let id):
            return "video(\(id))"
        case .invalid(let value):
            return value.isEmpty ? "invalid(empty)" : "invalid(\(value))"
        }
    }
}

enum ShortsPlayerStateReducer {
    struct State: Equatable {
        let activeVideoID: String?
        let isPlaying: Bool
    }

    static func togglePlayback(
        currentVideoID: String?,
        isPlaying: Bool,
        tappedVideoID: String
    ) -> State {
        let normalizedVideoID = tappedVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoID.isEmpty else {
            return State(activeVideoID: currentVideoID, isPlaying: isPlaying)
        }

        if currentVideoID == normalizedVideoID {
            return State(activeVideoID: normalizedVideoID, isPlaying: !isPlaying)
        }

        return State(activeVideoID: normalizedVideoID, isPlaying: true)
    }

    static func visibleItemChanged(
        currentVideoID: String?,
        isPlaying: Bool,
        visibleVideoID: String
    ) -> State {
        let normalizedVideoID = visibleVideoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoID.isEmpty else {
            return State(activeVideoID: currentVideoID, isPlaying: isPlaying)
        }

        if currentVideoID == normalizedVideoID {
            return State(activeVideoID: normalizedVideoID, isPlaying: isPlaying)
        }

        return State(activeVideoID: normalizedVideoID, isPlaying: true)
    }

    static func pauseForOriginal() -> State {
        State(activeVideoID: nil, isPlaying: false)
    }
}
