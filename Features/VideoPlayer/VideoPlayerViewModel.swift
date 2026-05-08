import AVFoundation
import Foundation

enum VideoQualitySelectionSource: String {
    case actionSheet
    case chip
    case programmatic
}

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published private(set) var viewState: VideoPlayerViewState
    @Published private(set) var player: AVPlayer?

    private let fetchStreamUseCase: FetchVideoStreamUseCase
    private let setLikeUseCase: SetVideoLikeUseCase
    private let appConfiguration: AppConfiguration
    private let tokenStore: (any TokenStore)?
    private let protectedResourceHeaderProvider: ProtectedResourceHeaderProvider?
    private let imageLoader: (any AuthorizedImageLoading)?
    private let nowPlayingManager: NowPlayingManager
    private let context: VideoPlaybackContext
    private let onVideoUpdated: (Video) -> Void
    private let playbackVideoID: String
    private let logger = Logger(category: "VideoPlayer")
    private let qualityLogger = Logger(category: "VideoQuality")
    private let streamServerFailureMessage = "영상 스트리밍 주소가 만료되었거나 서버 설정이 올바르지 않습니다. 다시 시도해 주세요."

    private var hasLoadedInitialStream = false
    private var activeStreamRequestKey: String?
    private var streamIssuedAt: Date?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var pendingSeekTime: CMTime?
    private var pendingResumeAfterReady = false
    private var playbackGeneration = 0
    private var didLogATSConfiguration = false
    private var attemptedFallbackQualities = Set<String>()
    private var currentAttemptQuality: String?
    private var currentAttemptAuthMode: HLSAuthMode?
    private var currentAttemptFailureMessage: String?
    private var didRefreshAfterHLSServiceMismatch = false
    private var subtitleGeneration = 0
    private var subtitleCues: [VideoSubtitleCue] = []
    private let subtitlePreferenceStore = VideoSubtitlePreferenceStore()
    private var didTearDown = false
    private var isDetachedFromView = false
    private var lastKnownDuration: Double?

    init(
        video: Video,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        appConfiguration: AppConfiguration = AppConfiguration(),
        tokenStore: (any TokenStore)? = nil,
        imageLoader: (any AuthorizedImageLoading)? = nil,
        nowPlayingManager: NowPlayingManager = .shared,
        context: VideoPlaybackContext = .detail,
        onVideoUpdated: @escaping (Video) -> Void = { _ in }
    ) {
        self.viewState = VideoPlayerViewState(video: video)
        self.fetchStreamUseCase = fetchStreamUseCase
        self.setLikeUseCase = setLikeUseCase
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
        self.protectedResourceHeaderProvider = tokenStore.map {
            ProtectedResourceHeaderProvider(configuration: appConfiguration, tokenStore: $0)
        }
        self.imageLoader = imageLoader
        self.nowPlayingManager = nowPlayingManager
        self.context = context
        self.onVideoUpdated = onVideoUpdated
        self.playbackVideoID = video.videoId
    }

    convenience init(
        video: Video,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        onVideoUpdated: @escaping (Video) -> Void = { _ in }
    ) {
        self.init(
            video: video,
            fetchStreamUseCase: fetchStreamUseCase,
            setLikeUseCase: setLikeUseCase,
            appConfiguration: AppConfiguration(),
            tokenStore: nil,
            imageLoader: nil,
            context: .detail,
            onVideoUpdated: onVideoUpdated
        )
    }

    deinit {
        itemStatusObservation?.invalidate()
        playerStatusObservation?.invalidate()
        playerTimeControlObservation?.invalidate()
        Task { @MainActor [videoId = playbackVideoID, context] in
            VideoPlaybackCoordinator.shared.deactivate(videoId: videoId, context: context)
        }
    }

    func loadStreamIfNeeded() async {
        guard !hasLoadedInitialStream else { return }
        if adoptTransferredPlaybackIfAvailable() {
            hasLoadedInitialStream = true
            return
        }
        hasLoadedInitialStream = true
        await loadStream(shouldAutoplay: true, reason: "initialLoad")
    }

    func retryStream() async {
        cancelPendingPlayback(reason: "retry")
        attemptedFallbackQualities.removeAll()
        didRefreshAfterHLSServiceMismatch = false
        viewState.effectivePlaybackQuality = nil
        await loadStream(shouldAutoplay: true, reason: "retry")
    }

    func play() {
        didTearDown = false
        if isDetachedFromView {
            isDetachedFromView = false
            if let player, let item = player.currentItem {
                activatePlaybackCoordinator(for: player, item: item, generation: playbackGeneration)
            }
        }
        switch viewState.playbackState {
        case .ready, .paused:
            break
        default:
            return
        }
        player?.play()
        setPlaybackState(.playing)
    }

    func pause() {
        player?.pause()
        if case .playing = viewState.playbackState {
            setPlaybackState(.paused)
        }
    }

    func tearDown() {
        guard !didTearDown else {
            logger.debug("[VideoPlayer] context=\(context.rawValue) cleanup skipped reason=alreadyRemoved videoId=\(viewState.video.videoId)")
            return
        }
        didTearDown = true
        isDetachedFromView = true
        cancelPendingPlayback(reason: "viewDisappear")
        cancelSubtitleLoading(reason: "viewDisappear")
        removeCurrentItemObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        nowPlayingManager.clear(reason: "dismissed")
        VideoPlaybackCoordinator.shared.deactivate(videoId: viewState.video.videoId, context: context)
        playerStatusObservation?.invalidate()
        playerStatusObservation = nil
        playerTimeControlObservation?.invalidate()
        playerTimeControlObservation = nil
        viewState.currentTime = 0
        viewState.duration = nil
        lastKnownDuration = nil
        viewState.activeCaptionText = nil
    }

    func detachFromView(reason: String) {
        guard !isDetachedFromView else {
            logger.debug("[VideoPlayer] context=\(context.rawValue) cleanup skipped reason=alreadyDetached videoId=\(viewState.video.videoId)")
            return
        }
        isDetachedFromView = true
        if reason == "openOriginal",
           context == .shorts,
           VideoPlaybackCoordinator.shared.currentContext == .detail,
           VideoPlaybackCoordinator.shared.currentVideoId == viewState.video.videoId {
            removeCurrentItemObserver()
            playerStatusObservation?.invalidate()
            playerStatusObservation = nil
            playerTimeControlObservation?.invalidate()
            playerTimeControlObservation = nil
            cancelSubtitleLoading(reason: reason)
            logger.debug("[ShortsPlayer] global cleanup skipped reason=ownershipMovedToDetail videoId=\(viewState.video.videoId)")
            logger.debug("[ShortsPlayer] detachOnly completed videoId=\(viewState.video.videoId) didNotStopCoordinator=true didNotRemoveGlobalTimeObserver=true")
            logger.debug("[VideoPlayer] context=\(context.rawValue) detach reason=\(reason) videoId=\(viewState.video.videoId)")
            return
        }
        cancelPendingPlayback(reason: reason)
        player?.pause()
        VideoPlaybackCoordinator.shared.deactivate(videoId: viewState.video.videoId, context: context)
        if case .playing = viewState.playbackState {
            setPlaybackState(.paused)
        }
        logger.debug("[VideoPlayer] context=\(context.rawValue) detach reason=\(reason) videoId=\(viewState.video.videoId)")
    }

    func openQualityMenu() {
        let available = availableQualityTitles().joined(separator: ",")
        qualityLogger.debug(
            "[VideoQuality] actionSheet present current=\(viewState.qualityTitle) available=\(available)"
        )
        viewState.isQualityMenuPresented = true
    }

    func dismissQualityMenu() {
        viewState.isQualityMenuPresented = false
    }

    func selectQuality(_ quality: VideoStreamQuality?, source: VideoQualitySelectionSource = .programmatic) async {
        guard let stream = viewState.stream else { return }
        let previousUserSelected = viewState.userSelectedQuality
        let nextQuality = quality?.quality ?? "auto"

        attemptedFallbackQualities.removeAll()
        viewState.userSelectedQuality = nextQuality
        viewState.effectivePlaybackQuality = nextQuality == "auto" ? nil : nextQuality
        viewState.isQualityMenuPresented = false
        viewState.detailReason = nil

        if source == .actionSheet {
            qualityLogger.debug("[VideoQuality] actionSheet select quality=\(nextQuality)")
        }
        qualityLogger.debug(
            "[VideoQuality] userSelected quality=\(nextQuality) previousUserSelected=\(previousUserSelected)"
        )

        cancelPendingPlayback(reason: "userQualityChanged")
        guard previousUserSelected != nextQuality || viewState.playbackState.isFailure else { return }

        let resolvedQuality: ResolvedVideoQuality
        do {
            resolvedQuality = try resolveQuality(nextQuality, in: stream)
        } catch {
            viewState.detailReason = detailReason(for: error)
            setPlaybackState(.failed(userFacingPlaybackFailureMessage(forExplicitQuality: true)))
            logger.error("[VideoPlayer] context=\(context.rawValue) selected quality unavailable quality=\(nextQuality)")
            return
        }

        let currentTime = player?.currentTime() ?? .zero
        let shouldResume = viewState.playbackState == .playing
            || viewState.playbackState == .loadingStream
            || player?.timeControlStatus == .playing

        await replacePlayerItem(
            resolvedQuality: resolvedQuality,
            reason: "userQualityChanged",
            seekTime: currentTime,
            shouldResume: shouldResume,
            failureMessage: userFacingPlaybackFailureMessage(forExplicitQuality: nextQuality != "auto")
        )
    }

    func handlePlaybackFailure() {
        guard let item = player?.currentItem else {
            viewState.detailReason = "playerItemFailed"
            setPlaybackState(.failed(userFacingPlaybackFailureMessage(forExplicitQuality: viewState.userSelectedQuality != "auto")))
            logger.error("[VideoPlayer] context=\(context.rawValue) item failed videoId=\(viewState.video.videoId) reason=playbackFailure")
            return
        }

        Task {
            await handleItemFailure(
                item,
                quality: currentAttemptQuality ?? viewState.effectivePlaybackQuality ?? viewState.userSelectedQuality,
                generation: playbackGeneration,
                failureMessage: currentAttemptFailureMessage
            )
        }
    }

    func handlePlaybackStalled() {
        if isLikelyExpired() {
            viewState.detailReason = "playerPlaybackStalledExpired"
            setPlaybackState(.expiredOrUnavailable(streamServerFailureMessage))
            logger.error("[VideoPlayer] context=\(context.rawValue) item failed videoId=\(viewState.video.videoId) reason=playbackStalledExpired")
        }
    }

    func logCurrentItemErrorLog() {
        guard let item = player?.currentItem else { return }
        logItemErrorLog(for: item)
    }

    func logCurrentItemAccessLog() {
        guard let item = player?.currentItem else { return }
        logAccessLog(for: item)
    }

    func toggleLike() async {
        guard !viewState.isLikeUpdating else { return }

        let previousVideo = viewState.video
        let optimisticLikeStatus = !previousVideo.isLiked
        viewState.isLikeUpdating = true
        applyLikeStatus(optimisticLikeStatus)

        do {
            let confirmedLikeStatus = try await setLikeUseCase.execute(
                videoId: previousVideo.videoId,
                isLiked: optimisticLikeStatus
            )
            applyLikeStatus(confirmedLikeStatus)
        } catch {
            viewState.video = previousVideo
            viewState.toastMessage = resolveErrorMessage(error)
            onVideoUpdated(previousVideo)
        }

        viewState.isLikeUpdating = false
    }

    func clearToast() {
        viewState.toastMessage = nil
    }

    func openSubtitleMenu() {
        guard viewState.hasSubtitleOptions else { return }
        viewState.isSubtitleMenuPresented = true
    }

    func dismissSubtitleMenu() {
        viewState.isSubtitleMenuPresented = false
    }

    func setCaptionsEnabled(_ isEnabled: Bool) async {
        viewState.captionsEnabled = isEnabled
        viewState.activeCaptionText = nil
        subtitlePreferenceStore.saveEnabled(isEnabled)
        if isEnabled {
            await loadSelectedSubtitleIfNeeded(reason: "captionsEnabled")
            if let item = player?.currentItem {
                configureSystemSubtitleIfNeeded(for: item)
            }
        } else {
            cancelSubtitleLoading(reason: "captionsDisabled")
            deselectSystemSubtitlesIfNeeded()
        }
    }

    func selectSubtitle(_ subtitle: VideoSubtitle?) async {
        viewState.selectedSubtitleID = subtitle?.id
        viewState.captionsEnabled = subtitle != nil
        viewState.isSubtitleMenuPresented = false
        viewState.activeCaptionText = nil
        subtitlePreferenceStore.saveEnabled(subtitle != nil)
        subtitlePreferenceStore.saveSubtitleID(subtitle?.id)
        await loadSelectedSubtitleIfNeeded(reason: "subtitleSelected")
    }

    func selectSystemSubtitles() {
        viewState.selectedSubtitleID = nil
        viewState.captionsEnabled = true
        viewState.isSubtitleMenuPresented = false
        viewState.activeCaptionText = nil
        subtitlePreferenceStore.saveEnabled(true)
        subtitlePreferenceStore.saveSubtitleID(nil)
        cancelSubtitleLoading(reason: "systemSubtitleSelected")
        if let item = player?.currentItem {
            configureSystemSubtitleIfNeeded(for: item)
        }
    }

    func logNavigationRender() {
        logger.debug("[VideoNavigation] render customBackButton=true systemBackButtonHidden=true")
    }

    func handleBackTapped() {
        logger.debug("[VideoNavigation] back tapped source=customButton")
    }

    func togglePlayback() {
        switch viewState.playbackState {
        case .playing:
            pause()
        case .ready, .paused:
            play()
        default:
            break
        }
    }

    func beginScrubbing() {
        guard viewState.duration != nil else { return }
        viewState.isScrubbing = true
        logger.debug("[ShortsPlayer] seek started videoId=\(viewState.video.videoId)")
    }

    func updateScrubbing(progress: Double) {
        guard let duration = viewState.duration,
              duration.isFinite,
              duration > 0 else {
            return
        }

        let clampedProgress = min(max(progress, 0), 1)
        viewState.currentTime = duration * clampedProgress
        logger.debug("[ShortsPlayer] seek changed videoId=\(viewState.video.videoId) progress=\(String(format: "%.3f", clampedProgress))")
    }

    func endScrubbing(progress: Double) {
        viewState.isScrubbing = false
        logger.debug("[ShortsPlayer] seek ended videoId=\(viewState.video.videoId) progress=\(String(format: "%.3f", min(max(progress, 0), 1)))")
        seek(toProgress: progress)
    }

    func seek(by seconds: Double) {
        guard let duration = viewState.duration,
              duration.isFinite,
              duration > 0 else {
            return
        }

        let targetSeconds = min(max(viewState.currentTime + seconds, 0), duration)
        logger.debug("[ShortsPlayer] seek changed videoId=\(viewState.video.videoId) delta=\(Int(seconds)) target=\(Int(targetSeconds))")
        seek(toSeconds: targetSeconds)
    }

    func replay() {
        logger.debug("[ShortsPlayer] ended policy=replay videoId=\(viewState.video.videoId)")
        seek(toSeconds: 0)
        player?.play()
        nowPlayingManager.updatePlaybackState(player: player, duration: viewState.duration, elapsed: viewState.currentTime, rate: 1, force: true)
        setPlaybackState(.playing)
    }

    func handlePlaybackEnded() {
        setPlaybackState(.ready)
        nowPlayingManager.clear(reason: "ended")
    }

    func seek(toProgress progress: Double) {
        guard let duration = viewState.duration,
              duration.isFinite,
              duration > 0 else {
            return
        }

        let clampedProgress = min(max(progress, 0), 1)
        seek(toSeconds: duration * clampedProgress)
    }

    private func seek(toSeconds seconds: Double) {
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        viewState.currentTime = max(0, seconds)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        nowPlayingManager.updatePlaybackState(player: player, duration: viewState.duration, elapsed: seconds, force: true)
    }

    func qualityActionTitle(_ title: String, isSelected: Bool) -> String {
        isSelected ? "✓ \(title)" : title
    }

    private func loadStream(shouldAutoplay: Bool, reason: String) async {
        let videoID = viewState.video.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !videoID.isEmpty else {
            viewState.toastMessage = nil
            viewState.detailReason = "selectedQualityUnavailable"
            setPlaybackState(.failed("영상 정보를 불러올 수 없어요."))
            logger.error("[VideoPlayer] context=\(context.rawValue) invalid empty videoId")
            return
        }

        let requestKey = "\(videoID)|\(viewState.userSelectedQuality)"
        guard activeStreamRequestKey != requestKey else {
            logger.debug("[VideoPlayer] context=\(context.rawValue) skip duplicate requestStream key=\(requestKey)")
            return
        }
        activeStreamRequestKey = requestKey
        defer { activeStreamRequestKey = nil }

        setPlaybackState(.loadingStream)
        viewState.toastMessage = nil
        viewState.detailReason = nil
        logger.debug("[VideoPlayer] context=\(context.rawValue) state=loadingStream videoId=\(videoID)")

        do {
            if try await isMissingAuthenticatedSession() {
                logger.warning("[VideoPlayer] context=\(context.rawValue) stream skipped videoId=\(videoID) reason=missingAuthenticatedSession")
                setPlaybackState(.failed("로그인이 필요합니다."))
                return
            }

            let stream = try await fetchStreamUseCase.execute(videoId: videoID)
            guard !Task.isCancelled else {
                logger.debug("[VideoPlayer] context=\(context.rawValue) stream cancelled videoId=\(videoID) reason=taskCancelled")
                return
            }
            guard !isDetachedFromView, !didTearDown else {
                logger.debug("[ShortsOriginal] stale update ignored source=streamResolve videoId=\(videoID)")
                return
            }
            streamIssuedAt = Date()
            viewState.stream = stream
            configureSubtitleSelection(for: stream)
            Task { [weak self] in
                await self?.loadSelectedSubtitleIfNeeded(reason: "streamLoaded")
            }
            attemptedFallbackQualities.removeAll()
            didRefreshAfterHLSServiceMismatch = false

            let correctedQuality = correctedUserSelectedQuality(in: stream)
            if correctedQuality != viewState.userSelectedQuality {
                qualityLogger.warning(
                    "[VideoQuality] corrected selected quality from=\(viewState.userSelectedQuality) to=\(correctedQuality) reason=unavailable"
                )
                viewState.userSelectedQuality = correctedQuality
                viewState.detailReason = "selectedQualityUnavailable"
            }
            logStreamResponseDiagnostics(requestedVideoID: videoID, stream: stream)

#if DEBUG
            if HLSDebugDiagnosticsOptions.isEnabled {
                if let protectedResourceHeaders = try? await makeProtectedResourceHeaders() {
                    HLSPlaylistDiagnostics.run(
                        stream: stream,
                        seSACKey: appConfiguration.seSACKey,
                        protectedResourceHeaders: protectedResourceHeaders
                    )
                }
            }
#endif

            let resolvedQuality = try resolveQuality(viewState.userSelectedQuality, in: stream)
            await replacePlayerItem(
                resolvedQuality: resolvedQuality,
                reason: reason,
                seekTime: .zero,
                shouldResume: shouldAutoplay,
                failureMessage: userFacingPlaybackFailureMessage(forExplicitQuality: viewState.userSelectedQuality != "auto")
            )
        } catch {
            let message = resolveStreamErrorMessage(error)
            viewState.detailReason = detailReason(for: error)
            setPlaybackState(.failed(message))
            if case .forbidden = error as? NetworkError {
                logger.warning("[VideoPlayer] context=\(context.rawValue) stream forbidden videoId=\(videoID) keepSession=true")
            }
            logger.error("[VideoPlayer] context=\(context.rawValue) item failed videoId=\(viewState.video.videoId) error=\(error.localizedDescription)")
        }
    }

    private func setPlaybackState(_ state: VideoPlayerPlaybackState) {
        viewState.playbackState = state
        switch state {
        case .playing:
            logger.debug("[VideoPlayer] context=\(context.rawValue) state=playing videoId=\(viewState.video.videoId)")
            if canUpdateSharedPlaybackSideEffects {
                nowPlayingManager.updatePlaybackState(player: player, duration: viewState.duration, elapsed: viewState.currentTime, rate: 1, force: true)
            } else {
                logger.debug("[NowPlaying] update skipped reason=sessionMismatch videoId=\(viewState.video.videoId)")
            }
        case .paused:
            logger.debug("[VideoPlayer] context=\(context.rawValue) state=paused videoId=\(viewState.video.videoId)")
            if canUpdateSharedPlaybackSideEffects {
                nowPlayingManager.updatePlaybackState(player: player, duration: viewState.duration, elapsed: viewState.currentTime, rate: 0, force: true)
            } else {
                logger.debug("[NowPlaying] update skipped reason=sessionMismatch videoId=\(viewState.video.videoId)")
            }
        case .ready:
            logger.debug("[VideoPlayer] context=\(context.rawValue) state=ready videoId=\(viewState.video.videoId)")
            if canUpdateSharedPlaybackSideEffects {
                nowPlayingManager.updatePlaybackState(player: player, duration: viewState.duration, elapsed: viewState.currentTime, rate: 0, force: true)
            } else {
                logger.debug("[NowPlaying] update skipped reason=sessionMismatch videoId=\(viewState.video.videoId)")
            }
        case .failed, .expiredOrUnavailable:
            if canUpdateSharedPlaybackSideEffects {
                nowPlayingManager.clear(reason: "failed")
            } else {
                logger.debug("[NowPlaying] update skipped reason=sessionMismatch videoId=\(viewState.video.videoId)")
            }
        default:
            break
        }
    }

    private func loadNowPlayingArtworkIfNeeded() async {
        guard let imageLoader,
              let thumbnailURL = viewState.video.thumbnailURL,
              !thumbnailURL.isEmpty else {
            return
        }
        do {
            logger.debug("[NowPlaying] artwork load requested videoId=\(viewState.video.videoId) url=\(thumbnailURL)")
            let data = try await imageLoader.imageData(for: thumbnailURL)
            guard canUpdateSharedPlaybackSideEffects else {
                logger.debug("[NowPlaying] update skipped reason=sessionMismatch videoId=\(viewState.video.videoId)")
                return
            }
            nowPlayingManager.updateMetadata(video: viewState.video, artworkData: data)
        } catch {
            logger.debug("[NowPlaying] artwork fallback reason=loadFailed videoId=\(viewState.video.videoId)")
        }
    }

    private func availableQualityTitles() -> [String] {
        guard let stream = viewState.stream else {
            return ["auto"]
        }

        return ["auto"] + stream.qualities.map(\.quality)
    }

    private func isMissingAuthenticatedSession() async throws -> Bool {
        guard let tokenStore else { return false }
        return try await tokenStore.loadTokens() == nil
    }

    private func replacePlayerItem(
        resolvedQuality: ResolvedVideoQuality,
        reason: String,
        seekTime: CMTime,
        shouldResume: Bool,
        failureMessage: String?
    ) async {
        let generation = nextPlaybackGeneration()
        let descriptor = VideoURLLogDescriptor(url: resolvedQuality.url)
        logger.debug(
            "[VideoPlayer] context=\(context.rawValue) prepare item reason=\(reason) requested=\(resolvedQuality.identifier) playbackURLPath=\(descriptor.path) queryExists=\(descriptor.queryExists) queryKeys=\(descriptor.queryKeys) preserveTime=\(seekTime.seconds.isFinite ? seekTime.seconds : 0) generation=\(generation)"
        )
        logger.debug("[VideoPlayer] context=\(context.rawValue) selected quality=\(resolvedQuality.identifier) urlExists=\(!resolvedQuality.url.absoluteString.isEmpty)")
        logStreamURL(rawPath: resolvedQuality.rawPath, resolvedURL: resolvedQuality.url, quality: resolvedQuality.identifier)
        setPlaybackState(.loadingStream)
        currentAttemptQuality = resolvedQuality.identifier
        currentAttemptAuthMode = nil
        currentAttemptFailureMessage = failureMessage

        removeCurrentItemObserver()

        let item: AVPlayerItem
        let playbackCandidate: PlaybackCandidate
        do {
            let result = try await makeHLSPlayerItem(resolvedQuality: resolvedQuality)
            item = result.item
            playbackCandidate = result.candidate
        } catch {
            guard generation == playbackGeneration else {
                logger.debug(
                    "[VideoPlayer] context=\(context.rawValue) ignore stale item build failure generation=\(generation) current=\(playbackGeneration) quality=\(resolvedQuality.identifier)"
                )
                return
            }

            if let probeFailure = error as? HLSProbeFailure {
                attemptedFallbackQualities.insert(resolvedQuality.identifier)
                viewState.detailReason = probeFailure.detailReason
                if probeFailure.shouldRefreshStreamOnce,
                   await retryOnceAfterTerminalHLSAuthFailure(
                    failedQuality: resolvedQuality.identifier,
                    reason: probeFailure.refreshRetryReason,
                    seekTime: seekTime,
                    shouldResume: shouldResume,
                    failureMessage: failureMessage
                   ) {
                    return
                }

                setPlaybackState(.failed(userFacingHLSProbeFailureMessage()))
                logTerminalHLSAuthFailureIfNeeded(
                    probeFailure: probeFailure,
                    selectedQuality: resolvedQuality.identifier,
                    retryExhausted: true
                )
                logger.error("[VideoPlayer] context=\(context.rawValue) item failed videoId=\(viewState.video.videoId) error=\(probeFailure.detailReason)")
                return
            }

            viewState.detailReason = detailReason(for: error)
            setPlaybackState(.failed(failureMessage ?? userFacingPlaybackFailureMessage(forExplicitQuality: viewState.userSelectedQuality != "auto")))
            logger.error("[VideoPlayer] context=\(context.rawValue) item failed error=\(error.localizedDescription)")
            return
        }

        let playbackDescriptor = VideoURLLogDescriptor(url: playbackCandidate.url)
        currentAttemptQuality = playbackCandidate.quality
        currentAttemptAuthMode = playbackCandidate.authMode
        logger.debug(
            "[VideoPlayer] context=\(context.rawValue) replace item reason=\(reason) quality=\(playbackCandidate.quality) authMode=\(playbackCandidate.authMode.rawValue) hlsHeaderMode=\(playbackCandidate.authMode.rawValue) assetHeaders=true hasSeSACKeyHeader=true headerAuthorization=true headerContentType=false playbackURLPath=\(playbackDescriptor.path) queryExists=\(playbackDescriptor.queryExists) queryKeys=\(playbackDescriptor.queryKeys) preserveTime=\(seekTime.seconds.isFinite ? seekTime.seconds : 0) generation=\(generation)"
        )

        guard generation == playbackGeneration else {
            logger.debug(
                "[VideoPlayer] context=\(context.rawValue) ignore stale item build generation=\(generation) current=\(playbackGeneration) quality=\(resolvedQuality.identifier)"
            )
            return
        }

        pendingSeekTime = seekTime.seconds.isFinite && seekTime.seconds > 0 ? seekTime : nil
        pendingResumeAfterReady = shouldResume

        let targetPlayer: AVPlayer
        didTearDown = false
        isDetachedFromView = false
        if let player {
            targetPlayer = player
            installPlayerObserversIfNeeded(for: player)
            player.replaceCurrentItem(with: item)
        } else {
            targetPlayer = AVPlayer(playerItem: item)
            player = targetPlayer
            installPlayerObserversIfNeeded(for: targetPlayer)
        }
        nowPlayingManager.configureSessionIfNeeded(player: targetPlayer, videoId: viewState.video.videoId, context: context)
        nowPlayingManager.updateMetadata(video: viewState.video)
        Task { [weak self] in
            await self?.loadNowPlayingArtworkIfNeeded()
        }
        activatePlaybackCoordinator(for: targetPlayer, item: item, generation: generation)

        installItemStatusObserver(
            for: item,
            quality: playbackCandidate.quality,
            authMode: playbackCandidate.authMode,
            generation: generation,
            failureMessage: failureMessage
        )
    }

    private func handleItemFailure(
        _ item: AVPlayerItem,
        quality: String,
        generation: Int,
        failureMessage: String?
    ) async {
        guard generation == playbackGeneration else {
            logger.debug(
                "[VideoPlayer] ignore stale item status generation=\(generation) current=\(playbackGeneration) quality=\(quality)"
            )
            return
        }

        let itemError = item.error
        let nsError = itemError as NSError?
        let underlyingError = nsError?.userInfo[NSUnderlyingErrorKey] as? NSError
        let statusCodes = item.errorLog()?.events.map(\.errorStatusCode) ?? []
        let terminalStreamServerFailure = statusCodes.contains(420) || statusCodes.contains(444)
        let detailReason: String
        if statusCodes.contains(444) {
            detailReason = "hlsUnauthorizedEvenWithProtectedHeaders"
        } else if statusCodes.contains(420) {
            detailReason = "hlsRequiresServiceHeader"
        } else {
            detailReason = "playerItemFailed(\(nsError?.code ?? 0))"
        }
        viewState.detailReason = detailReason
        logger.error(
            "[VideoPlayer] context=\(context.rawValue) item status=failed requested=\(quality) userSelected=\(viewState.userSelectedQuality) error=\(itemError?.localizedDescription ?? "unknown") domain=\(nsError?.domain ?? "nil") code=\(nsError?.code ?? 0) detailReason=\(detailReason)"
        )
        logger.error(
            "[VideoPlayer] context=\(context.rawValue) item failed quality=\(quality) nsErrorDomain=\(nsError?.domain ?? "nil") nsErrorCode=\(nsError?.code ?? 0) underlying=\(underlyingError.map { "\($0.domain)(\($0.code))" } ?? "nil")"
        )
        logItemErrorLog(for: item)
        logAccessLog(for: item)
        if let playerError = player?.error {
            logger.error("[VideoPlayer] context=\(context.rawValue) player error=\(playerError.localizedDescription)")
        }
#if DEBUG
        debugLogPlayerFailure(item: item, player: player)
#endif

        attemptedFallbackQualities.insert(quality)
        let failedURL = (item.asset as? AVURLAsset)?.url
        if statusCodes.contains(where: { $0 == 420 || $0 == 444 }),
           await retryOnceAfterTerminalHLSAuthFailure(
            failedQuality: quality,
            reason: statusCodes.contains(444) ? "playerItem444ProtectedResourceUnauthorized" : "playerItem420RequiresServiceHeader",
            seekTime: player?.currentTime() ?? .zero,
            shouldResume: true,
            failureMessage: failureMessage
           ) {
            return
        }

        if shouldAttemptFallbackAfterItemFailure(quality: quality, statusCodes: statusCodes, nsError: nsError),
           let stream = viewState.stream,
           let nextQuality = nextFallbackQuality(
            afterFailedQuality: quality,
            failedURL: failedURL,
            in: stream
           ) {
            logger.warning(
                "[VideoPlayer] fallback start from=\(quality) next=\(nextQuality) reason=\(detailReason) code=\(nsError?.code ?? 0)"
            )
            do {
                let resolvedQuality = try resolveQuality(nextQuality, in: stream)
                viewState.effectivePlaybackQuality = nextQuality
                await replacePlayerItem(
                    resolvedQuality: resolvedQuality,
                    reason: "fallbackAfterFailure",
                    seekTime: player?.currentTime() ?? .zero,
                    shouldResume: true,
                    failureMessage: failureMessage
                )
                return
            } catch {
                attemptedFallbackQualities.insert(nextQuality)
                logger.error("[VideoPlayer] fallback resolve failed quality=\(nextQuality) reason=\(error.localizedDescription)")
            }
        }

        logger.error(
            "[VideoPlayer] fallback exhausted attempted=\(fallbackAttemptSummary(in: viewState.stream))"
        )
        viewState.detailReason = "quality=\(quality) \(detailReason)"
        if statusCodes.contains(420) {
            logger.error(
                "[VideoPlayer] failed reason=hlsRequiresServiceHeader videoId=\(viewState.video.videoId) responseVideoId=\(viewState.stream?.videoId ?? "nil") selectedQuality=\(quality) status=420 classification=hlsRequiresServiceHeader responseMessage=unavailableFromAVPlayerErrorLog hasSeSACKeyHeader=true headerAuthorization=true headerContentType=false retryAfterRefresh=\(didRefreshAfterHLSServiceMismatch ? "exhausted" : "notAttempted")"
            )
        } else if statusCodes.contains(444) {
            logger.error(
                "[VideoPlayer] failed reason=hlsUnauthorizedEvenWithProtectedHeaders videoId=\(viewState.video.videoId) responseVideoId=\(viewState.stream?.videoId ?? "nil") selectedQuality=\(quality) status=444 classification=hlsUnauthorizedEvenWithProtectedHeaders responseMessage=unavailableFromAVPlayerErrorLog hasSeSACKeyHeader=true headerAuthorization=true headerContentType=false retryAfterRefresh=\(didRefreshAfterHLSServiceMismatch ? "exhausted" : "notAttempted")"
            )
        }
        setPlaybackState(.failed(terminalStreamServerFailure ? streamServerFailureMessage : (failureMessage ?? userFacingPlaybackFailureMessage(forExplicitQuality: viewState.userSelectedQuality != "auto"))))
    }

    private func retryOnceAfterTerminalHLSAuthFailure(
        failedQuality: String,
        reason: String,
        seekTime: CMTime,
        shouldResume: Bool,
        failureMessage: String?
    ) async -> Bool {
        guard !didRefreshAfterHLSServiceMismatch else {
            logger.warning(
                "[VideoPlayer] HLS auth retry suppressed videoId=\(viewState.video.videoId) responseVideoId=\(viewState.stream?.videoId ?? "nil") selectedQuality=\(failedQuality) reason=\(reason) retryAfterRefresh=exhausted hasSeSACKeyHeader=true headerAuthorization=true headerContentType=false"
            )
            return false
        }

        didRefreshAfterHLSServiceMismatch = true
        let videoID = viewState.video.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !videoID.isEmpty else { return false }

        logger.warning(
            "[VideoPlayer] HLS auth failure refreshing stream once videoId=\(videoID) responseVideoId=\(viewState.stream?.videoId ?? "nil") selectedQuality=\(failedQuality) reason=\(reason) hasSeSACKeyHeader=true headerAuthorization=true headerContentType=false"
        )

        do {
            let stream = try await fetchStreamUseCase.execute(videoId: videoID)
            streamIssuedAt = Date()
            viewState.stream = stream
            configureSubtitleSelection(for: stream)
            Task { [weak self] in
                await self?.loadSelectedSubtitleIfNeeded(reason: "streamRefreshed")
            }
            logStreamResponseDiagnostics(requestedVideoID: videoID, stream: stream)

            let correctedQuality = correctedUserSelectedQuality(in: stream)
            if correctedQuality != viewState.userSelectedQuality {
                qualityLogger.warning(
                    "[VideoQuality] corrected selected quality from=\(viewState.userSelectedQuality) to=\(correctedQuality) reason=unavailableAfterHLSServiceMismatchRefresh"
                )
                viewState.userSelectedQuality = correctedQuality
                viewState.detailReason = "selectedQualityUnavailable"
            }

            let resolvedQuality = try resolveQuality(viewState.userSelectedQuality, in: stream)
            await replacePlayerItem(
                resolvedQuality: resolvedQuality,
                reason: "refreshAfterHLSServiceMismatch",
                seekTime: seekTime,
                shouldResume: shouldResume,
                failureMessage: failureMessage
            )
            return true
        } catch {
            logger.error(
                "[VideoPlayer] HLS auth refresh failed videoId=\(videoID) selectedQuality=\(failedQuality) reason=\(error.localizedDescription)"
            )
            return false
        }
    }

    private func logTerminalHLSAuthFailureIfNeeded(
        probeFailure: HLSProbeFailure,
        selectedQuality: String,
        retryExhausted: Bool
    ) {
        guard let result = probeFailure.results.last,
              result.classification.isTerminalHLSAuthFailure else {
            return
        }

        let descriptor = VideoURLLogDescriptor(url: result.candidate.url)
        logger.error(
            "[VideoPlayer] failed reason=\(result.classification.rawValue) videoId=\(result.candidate.requestedVideoID) responseVideoId=\(result.candidate.responseVideoID) selectedQuality=\(selectedQuality) resolvedHLSHost=\(descriptor.host) resolvedHLSPort=\(descriptor.port) resolvedHLSPath=\(descriptor.path) queryKeys=\(descriptor.queryKeys) tokenLengthPreserved=\(result.tokenLengthPreserved) hasSeSACKeyHeader=\(result.headerSnapshot.hasSeSACKey) status=\(result.statusCode) responseMessage=\(result.bodyPrefix ?? "nil") classification=\(result.classification.rawValue) headerAuthorization=\(result.headerSnapshot.hasAuthorization) headerContentType=\(result.headerSnapshot.hasContentType) retryAfterRefresh=\(retryExhausted ? "exhausted" : "notExhausted")"
        )
    }

    private func correctedUserSelectedQuality(in stream: VideoStream) -> String {
        if viewState.userSelectedQuality == "auto" {
            return "auto"
        }

        if stream.qualities.contains(where: { $0.quality == viewState.userSelectedQuality }) {
            return viewState.userSelectedQuality
        }

        return "auto"
    }

    private func resolveQuality(_ quality: String, in stream: VideoStream) throws -> ResolvedVideoQuality {
        if quality == "auto" {
            return ResolvedVideoQuality(
                identifier: "auto",
                url: stream.streamURL,
                rawPath: stream.streamURLPath
            )
        }

        guard let streamQuality = stream.qualities.first(where: { $0.quality == quality }) else {
            throw VideoPlaybackSelectionError.selectedQualityUnavailable(quality)
        }

        return ResolvedVideoQuality(
            identifier: streamQuality.quality,
            url: streamQuality.url,
            rawPath: streamQuality.urlPath
        )
    }

    private func nextFallbackQuality(afterFailedQuality failedQuality: String, failedURL: URL?, in stream: VideoStream) -> String? {
        guard viewState.userSelectedQuality == "auto" else {
            return nil
        }

        let sequence = fallbackSequence(in: stream)
        return sequence.first { quality in
            guard quality != failedQuality,
                  !attemptedFallbackQualities.contains(quality),
                  let resolvedQuality = try? resolveQuality(quality, in: stream) else {
                return false
            }

            guard let failedURL else { return true }
            return resolvedQuality.url.absoluteString != failedURL.absoluteString
        }
    }

    private func shouldAttemptFallbackAfterItemFailure(quality: String, statusCodes: [Int], nsError: NSError?) -> Bool {
        if statusCodes.contains(where: { $0 == 420 || $0 == 444 }) {
            return false
        }

        if quality != "auto",
           statusCodes.contains(where: Self.isQualityFallbackHTTPStatus) {
            return true
        }

        guard statusCodes.isEmpty,
              let nsError,
              nsError.domain == NSURLErrorDomain else {
            return false
        }

        return Self.isTransientURLErrorCode(nsError.code)
    }

    private static func isQualityFallbackHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 404 || (500...599).contains(statusCode)
    }

    private static func isTransientURLErrorCode(_ code: Int) -> Bool {
        [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet
        ].contains(code)
    }

    private func fallbackSequence(in stream: VideoStream) -> [String] {
        let available = Set(stream.qualities.map(\.quality))
        return ["auto", "1080p", "720p", "480p"].filter { quality in
            quality == "auto" || available.contains(quality)
        }
    }

    private func fallbackAttemptSummary(in stream: VideoStream?) -> String {
        guard let stream else {
            return attemptedFallbackQualities.sorted().joined(separator: ",")
        }

        let ordered = fallbackSequence(in: stream).filter { attemptedFallbackQualities.contains($0) }
        let extra = attemptedFallbackQualities
            .filter { !ordered.contains($0) }
            .sorted()
        return (ordered + extra).joined(separator: ",")
    }

    private func logStreamURL(rawPath: String, resolvedURL: URL, quality: String) {
        let rawDescriptor = VideoURLLogDescriptor(rawValue: rawPath)
        logger.debug(
            "[VideoPlayer] stream raw quality=\(quality) path=\(rawDescriptor.path) ext=\(rawDescriptor.ext) queryExists=\(rawDescriptor.queryExists) queryKeys=\(rawDescriptor.queryKeys) queryKeyCount=\(rawDescriptor.queryKeyCount) rawQueryLength=\(rawDescriptor.rawQueryLength) percentEncodedQueryLength=\(rawDescriptor.percentEncodedQueryLength) tokenLength=\(rawDescriptor.tokenValueLength) maskedQuery=\(rawDescriptor.maskedQuery)"
        )

        let resolvedDescriptor = VideoURLLogDescriptor(url: resolvedURL)
        logger.debug(
            "[VideoPlayer] stream resolved quality=\(quality) scheme=\(resolvedDescriptor.scheme) host=\(resolvedDescriptor.host) port=\(resolvedDescriptor.port) path=\(resolvedDescriptor.path) ext=\(resolvedDescriptor.ext) queryExists=\(resolvedDescriptor.queryExists) queryKeys=\(resolvedDescriptor.queryKeys) queryKeyCount=\(resolvedDescriptor.queryKeyCount) rawQueryLength=\(resolvedDescriptor.rawQueryLength) percentEncodedQueryLength=\(resolvedDescriptor.percentEncodedQueryLength) tokenLength=\(resolvedDescriptor.tokenValueLength) tokenLengthPreserved=\(rawDescriptor.tokenValueLength == 0 || rawDescriptor.tokenValueLength == resolvedDescriptor.tokenValueLength) maskedQuery=\(resolvedDescriptor.maskedQuery)"
        )
    }

    private func logStreamResponseDiagnostics(requestedVideoID: String, stream: VideoStream) {
        let streamDescriptor = VideoURLLogDescriptor(rawValue: stream.streamURLPath)
        logger.debug(
            "[VideoStream] selectedVideoId=\(requestedVideoID) selectedTitle=\(viewState.video.title) responseVideoId=\(stream.videoId) streamPath=\(streamDescriptor.path) streamQueryKeys=\(streamDescriptor.queryKeys) selectedQuality=\(viewState.userSelectedQuality)"
        )

        if !stream.videoId.isEmpty,
           stream.videoId != requestedVideoID {
            logger.warning(
                "WARN [VideoStreamMismatch] requestedVideoId=\(requestedVideoID) responseVideoId=\(stream.videoId) streamPath=\(streamDescriptor.path)"
            )
        }

        if let selectedAsset = selectedVideoAssetIdentity(),
           !streamDescriptor.path.contains(selectedAsset.stem) {
            logger.warning(
                "WARN [VideoAssetMismatch] selectedThumbnail=\(selectedAsset.displayName) streamPath=\(streamDescriptor.path)"
            )
        }
    }

    private func selectedVideoAssetIdentity() -> (displayName: String, stem: String)? {
        if let thumbnailFileName = viewState.video.thumbnailURL.flatMap({ URL(string: $0)?.lastPathComponent }),
           let stem = Self.assetStem(from: thumbnailFileName) {
            return (thumbnailFileName, stem)
        }

        guard let stem = Self.assetStem(from: viewState.video.fileName) else { return nil }
        return (viewState.video.fileName, stem)
    }

    private static func assetStem(from fileName: String) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lastComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        let stem = (lastComponent as NSString).deletingPathExtension
        return stem.isEmpty ? nil : stem
    }

    private func logATSConfigurationIfNeeded(for url: URL) {
        guard !didLogATSConfiguration,
              url.scheme?.lowercased() == "http" else {
            return
        }
        didLogATSConfiguration = true

        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        let exceptionDomains = ats?["NSExceptionDomains"] as? [String: Any]
        let domainPolicy = exceptionDomains?[url.host ?? ""] as? [String: Any]
        let allowsDomainHTTP = domainPolicy?["NSExceptionAllowsInsecureHTTPLoads"] as? Bool
            ?? domainPolicy?["NSTemporaryExceptionAllowsInsecureHTTPLoads"] as? Bool
            ?? false
        let allowsMediaHTTP = ats?["NSAllowsArbitraryLoadsForMedia"] as? Bool ?? false
        let allowsAllHTTP = ats?["NSAllowsArbitraryLoads"] as? Bool ?? false
        logger.debug(
            "[VideoPlayer] ats scheme=http host=\(url.host ?? "nil") domainExceptionAllowsHTTP=\(allowsDomainHTTP) allowsMediaHTTP=\(allowsMediaHTTP) allowsArbitraryLoads=\(allowsAllHTTP)"
        )
        if !allowsMediaHTTP {
            viewState.detailReason = "atsMediaHTTPDisabled"
        }
    }

    private func makeHLSPlayerItem(
        resolvedQuality: ResolvedVideoQuality
    ) async throws -> (item: AVPlayerItem, candidate: PlaybackCandidate) {
        guard let stream = viewState.stream else {
            throw VideoPlaybackSelectionError.selectedQualityUnavailable(resolvedQuality.identifier)
        }
        let protectedResourceHeaders = try await makeProtectedResourceHeaders()
        let playbackCandidate = try await HLSProbeService.resolvePlaybackCandidate(
            selectedQuality: resolvedQuality.identifier,
            stream: stream,
            requestedVideoID: viewState.video.videoId,
            seSACKey: appConfiguration.seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
        let descriptor = VideoURLLogDescriptor(url: playbackCandidate.url)
        let headerSnapshot = HLSHeaderSnapshot(headers: protectedResourceHeaders)
        let assetOptions = HLSPlaybackHeaderOptions.assetOptions(headers: protectedResourceHeaders)
        logger.debug(
            "[VideoPlayer] createAsset hlsAuthMode=\(playbackCandidate.authMode.rawValue) quality=\(playbackCandidate.quality) url=\(descriptor.redactedAbsoluteString) assetHeaders=true queryExists=\(descriptor.queryExists) queryKeys=\(descriptor.queryKeys) queryKeyCount=\(descriptor.queryKeyCount) rawQueryLength=\(descriptor.rawQueryLength) percentEncodedQueryLength=\(descriptor.percentEncodedQueryLength) hasAuthorization=\(headerSnapshot.hasAuthorization) hasSeSACKey=\(headerSnapshot.hasSeSACKey) headerContentType=\(headerSnapshot.hasContentType)"
        )
        logger.debug("[VideoPlayer] hlsAuthMode=\(playbackCandidate.authMode.rawValue) headerSeSACKey=\(headerSnapshot.hasSeSACKey) headerAuthorization=\(headerSnapshot.hasAuthorization) headerContentType=\(headerSnapshot.hasContentType)")
#if DEBUG
        VideoStreamingDebugLogger.logSelected(
            source: debugSelectedSource(for: playbackCandidate.quality, in: stream),
            quality: playbackCandidate.quality,
            url: playbackCandidate.url
        )
#endif
        logATSConfigurationIfNeeded(for: playbackCandidate.url)

#if DEBUG
        VideoStreamingDebugLogger.logFinalPlayerURL(action: "create AVURLAsset", url: playbackCandidate.url)
#endif
        // AVPlayer resolves every HLS URI inside the master/variant playlists itself.
        // When the server uses token query auth, every playlist, subtitle, and segment
        // URI in the manifest must include that token (for example
        // subtitles.ko.vtt?token=..., 720p/index.m3u8?token=..., segment001.m4s?token=...)
        // or the server must authorize child resources from the master token session/cookie.
        // VTT subtitle responses must start with WEBVTT and use text/vtt or a compatible text content type.
        // The client cannot append token queries to AVPlayer's internal subtitle/segment requests.
        let asset = AVURLAsset(url: playbackCandidate.url, options: assetOptions)
#if DEBUG
        VideoStreamingDebugLogger.logFinalPlayerURL(action: "create AVPlayerItem", url: playbackCandidate.url)
#endif
        return (AVPlayerItem(asset: asset), playbackCandidate)
    }

    private func makeProtectedResourceHeaders() async throws -> [String: String] {
        guard let protectedResourceHeaderProvider else {
            throw NetworkError.unauthorized
        }
        return try await protectedResourceHeaderProvider.makeHeaders()
    }

    private func installPlayerObserversIfNeeded(for player: AVPlayer) {
        playerStatusObservation?.invalidate()
        playerTimeControlObservation?.invalidate()

        playerStatusObservation = player.observe(\.status, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                guard let self else { return }
                if observedPlayer.status == .failed {
                    self.logger.error("[VideoPlayer] context=\(self.context.rawValue) player error=\(observedPlayer.error?.localizedDescription ?? "unknown")")
#if DEBUG
                    self.debugLogPlayerError(observedPlayer, item: observedPlayer.currentItem)
#endif
                }
            }
        }

        playerTimeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                guard let self else { return }
                if let error = observedPlayer.error {
                    self.logger.error("[VideoPlayer] context=\(self.context.rawValue) player error=\(error.localizedDescription)")
#if DEBUG
                    self.debugLogPlayerError(observedPlayer, item: observedPlayer.currentItem)
#endif
                }
            }
        }
    }

    private func installItemStatusObserver(
        for item: AVPlayerItem,
        quality: String,
        authMode: HLSAuthMode,
        generation: Int,
        failureMessage: String?
    ) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] observedItem, _ in
            Task { @MainActor in
                guard let self, item === observedItem else { return }
                guard generation == self.playbackGeneration else {
                    self.logger.debug(
                        "[VideoPlayer] context=\(self.context.rawValue) ignore stale item status generation=\(generation) current=\(self.playbackGeneration) quality=\(quality)"
                    )
                    return
                }
                switch observedItem.status {
                case .readyToPlay:
                    self.logger.debug(
                        "[VideoPlayer] context=\(self.context.rawValue) itemReadyToPlay videoId=\(self.viewState.video.videoId) quality=\(quality) authMode=\(authMode.rawValue)"
                    )
                    self.viewState.effectivePlaybackQuality = quality
                    self.viewState.detailReason = nil
                    self.updatePlaybackTiming(from: observedItem)
                    self.configureSystemSubtitleIfNeeded(for: observedItem)
                    self.logAccessLog(for: observedItem)
                    let seekTime = self.pendingSeekTime
                    let shouldResume = self.pendingResumeAfterReady
                    self.pendingSeekTime = nil
                    self.pendingResumeAfterReady = false
                    self.setPlaybackState(.ready)

                    if let seekTime {
                        observedItem.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            Task { @MainActor in
                                guard let self, generation == self.playbackGeneration else { return }
                                if shouldResume {
                                    self.player?.play()
                                    self.setPlaybackState(.playing)
                                }
                            }
                        }
                    } else if shouldResume {
                        self.player?.play()
                        self.setPlaybackState(.playing)
                    }
                case .failed:
                    await self.handleItemFailure(
                        observedItem,
                        quality: quality,
                        generation: generation,
                        failureMessage: failureMessage
                    )
                case .unknown:
                    self.logger.debug(
                        "[VideoPlayer] context=\(self.context.rawValue) item status=unknown videoID=\(self.viewState.video.videoId) quality=\(quality) generation=\(generation)"
                    )
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func removeCurrentItemObserver() {
        guard itemStatusObservation != nil else {
            logger.warning("[VideoPlayer] observer cleanup skipped reason=alreadyRemoved context=\(context.rawValue)")
            return
        }
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
    }

    private func nextPlaybackGeneration() -> Int {
        playbackGeneration += 1
        return playbackGeneration
    }

    private func cancelPendingPlayback(reason: String) {
        playbackGeneration += 1
        logger.debug("[VideoPlayer] cancelPendingPlayback generation=\(playbackGeneration) reason=\(reason)")
    }

    private func logItemErrorLog(for item: AVPlayerItem) {
        guard let events = item.errorLog()?.events,
              !events.isEmpty else {
            logger.error("[VideoPlayer] item errorLog empty=true")
            return
        }

        logger.error("[VideoPlayer] errorLog event count=\(events.count)")
        for event in events {
            let uri = event.uri.map { VideoURLLogDescriptor(rawValue: $0).redactedAbsoluteString } ?? "nil"
            logger.error(
                "[VideoPlayer] errorLog event uri=\(uri) statusCode=\(event.errorStatusCode) errorStatusCode=\(event.errorStatusCode) serverAddress=\(event.serverAddress ?? "nil") playbackSessionID=\(event.playbackSessionID ?? "nil") errorDomain=\(event.errorDomain) errorComment=\(event.errorComment ?? "nil")"
            )
            if [401, 403, 420, 444].contains(event.errorStatusCode) {
                let resourceKind = hlsResourceKind(from: event.uri)
                logger.error(
                    "[VideoPlayer] failed reason=\(resourceKind)Unauthorized status=\(event.errorStatusCode) hlsAuthMode=\(currentAttemptAuthMode?.rawValue ?? "unknown") headerAuthorization=true headerSeSACKey=true headerContentType=false"
                )
            }
        }
    }

    private func hlsResourceKind(from uri: String?) -> String {
        guard let uri,
              let url = URL(string: uri) else {
            return "hlsRequest"
        }

        let path = url.path.lowercased()
        if path.hasSuffix(".m3u8") {
            return path.contains("master") ? "masterPlaylist" : "variantPlaylist"
        }

        if path.hasSuffix(".ts")
            || path.hasSuffix(".m4s")
            || path.hasSuffix(".aac")
            || path.hasSuffix(".vtt") {
            return "segment"
        }

        return "hlsRequest"
    }

    private func logAccessLog(for item: AVPlayerItem) {
        guard let events = item.accessLog()?.events,
              !events.isEmpty else {
            logger.debug("[VideoPlayer] accessLog empty=true")
            return
        }

        logger.debug("[VideoPlayer] accessLog event count=\(events.count)")
        for event in events.suffix(3) {
            logger.debug(
                "[VideoPlayer] accessLog indicatedBitrate=\(event.indicatedBitrate) observedBitrate=\(event.observedBitrate) segmentsDownloadedDuration=\(event.segmentsDownloadedDuration) durationWatched=\(event.durationWatched) numberOfStalls=\(event.numberOfStalls)"
            )
        }
    }

    private func applyLikeStatus(_ isLiked: Bool) {
        viewState.video = viewState.video.updatingLikeStatus(isLiked)
        onVideoUpdated(viewState.video)
    }

    private func isLikelyExpired() -> Bool {
        guard let streamIssuedAt else { return false }
        let tokenLifetime = max(viewState.video.duration * 1.5, 60)
        return Date().timeIntervalSince(streamIssuedAt) >= tokenLifetime
    }

    private func userFacingPlaybackFailureMessage(forExplicitQuality isExplicitQuality: Bool) -> String {
        if isExplicitQuality {
            return "선택한 화질을 재생할 수 없습니다.\n네트워크 또는 스트리밍 주소를 확인해주세요."
        }
        return "영상을 재생하지 못했습니다.\n네트워크 또는 스트리밍 주소를 확인해주세요."
    }

    private func userFacingHLSProbeFailureMessage() -> String {
#if DEBUG
        return "영상 재생 준비에 실패했습니다."
#else
        return "영상 재생 준비에 실패했습니다. 다시 시도해 주세요."
#endif
    }

    private func resolveStreamErrorMessage(_ error: Error) -> String {
        if case .invalidVideoId = error as? VideoStreamRequestError {
            return "영상 정보를 불러올 수 없어요."
        }

        if case .forbidden = error as? NetworkError {
            return "이 영상을 재생할 수 없어요."
        }

        if case .notFound = error as? NetworkError {
            return "비디오를 찾을 수 없습니다."
        }

        if let networkError = error as? NetworkError,
           networkError.isAuthenticationFailure {
            return "로그인이 필요합니다."
        }

        return "영상을 불러오지 못했습니다."
    }

    private func detailReason(for error: Error) -> String {
        if let selectionError = error as? VideoPlaybackSelectionError {
            return selectionError.detailReason
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "playerItemFailed(\(nsError.code))"
        }

        return error.localizedDescription
    }

    private func resolveErrorMessage(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func activatePlaybackCoordinator(for player: AVPlayer, item: AVPlayerItem, generation: Int) {
        VideoPlaybackCoordinator.shared.activate(
            player: player,
            videoId: viewState.video.videoId,
            context: context,
            item: item,
            generation: generation,
            stream: viewState.stream,
            onTick: { [weak self] tick in
                self?.handlePlaybackTick(tick)
            }
        )
    }

    private func handlePlaybackTick(_ tick: VideoPlaybackTick) {
        guard tick.videoId == viewState.video.videoId,
              tick.context == context,
              VideoPlaybackCoordinator.shared.isCurrentSession(tick.sessionId, videoId: tick.videoId, context: context, generation: tick.generation),
              tick.generation == playbackGeneration else {
            logger.debug("[PlayerTimeObserver] tick skipped reason=inactiveSession videoId=\(tick.videoId)")
            return
        }
        guard let currentPlayer = player,
              currentPlayer === tick.player,
              currentPlayer.currentItem === tick.item else {
            logger.debug("[PlayerTimeObserver] tick skipped reason=inactiveSession videoId=\(tick.videoId)")
            return
        }
        guard let elapsed = VideoPlaybackTiming.safeSeconds(tick.time) else {
            logger.debug("[PlayerTimeObserver] tick skipped reason=invalidTime videoId=\(tick.videoId)")
            return
        }

        if !viewState.isScrubbing {
            viewState.currentTime = elapsed
        }
        updatePlaybackTiming(from: tick.item)
        nowPlayingManager.updatePlaybackState(player: tick.player, duration: viewState.duration, elapsed: viewState.currentTime)
        updateActiveCaption(at: viewState.currentTime)
        logger.debug("[PlayerTimeObserver] tick handled elapsed=\(Int(viewState.currentTime)) duration=\(Int(viewState.duration ?? 0)) rate=\(tick.player.rate)")
    }

    private var canUpdateSharedPlaybackSideEffects: Bool {
        if VideoPlaybackCoordinator.shared.currentVideoId == nil {
            return true
        }
        guard let player else { return false }
        guard VideoPlaybackCoordinator.shared.isCurrentSession(
            VideoPlaybackCoordinator.shared.currentSessionId,
            videoId: viewState.video.videoId,
            context: context
        ) else {
            return false
        }
        return VideoPlaybackCoordinator.shared.currentPlaybackSession(videoId: viewState.video.videoId, context: context)?.player === player
    }

    private func adoptTransferredPlaybackIfAvailable() -> Bool {
        guard context == .detail,
              let session = VideoPlaybackCoordinator.shared.currentPlaybackSession(
                videoId: viewState.video.videoId,
                context: .detail
              ) else {
            return false
        }

        didTearDown = false
        isDetachedFromView = false
        player = session.player
        if let stream = session.stream {
            viewState.stream = stream
            configureSubtitleSelection(for: stream)
        }
        if let generation = session.itemGeneration {
            playbackGeneration = generation
        }
        installPlayerObserversIfNeeded(for: session.player)
        installItemStatusObserver(
            for: session.item,
            quality: viewState.effectivePlaybackQuality ?? viewState.userSelectedQuality,
            authMode: currentAttemptAuthMode ?? .tokenOnly,
            generation: playbackGeneration,
            failureMessage: nil
        )
        updatePlaybackTiming(from: session.item)
        nowPlayingManager.configureSessionIfNeeded(player: session.player, videoId: viewState.video.videoId, context: context)
        activatePlaybackCoordinator(for: session.player, item: session.item, generation: playbackGeneration)
        setPlaybackState(session.player.rate == 0 ? .ready : .playing)
        logger.debug("[VideoPlayer] context=detail adoptedTransferredPlayback videoId=\(viewState.video.videoId) sessionId=\(session.sessionId ?? "nil")")
        return true
    }

    private func updatePlaybackTiming(from item: AVPlayerItem?) {
        guard let item else {
            if let lastKnownDuration {
                viewState.duration = lastKnownDuration
                logger.debug("[NowPlayingUX] duration preserved source=previousSession duration=\(Int(lastKnownDuration))")
            } else {
                viewState.duration = nil
            }
            return
        }

        if let durationSeconds = VideoPlaybackTiming.safeSeconds(item.duration), durationSeconds > 0 {
            viewState.duration = durationSeconds
            lastKnownDuration = durationSeconds
        } else if let lastKnownDuration {
            viewState.duration = lastKnownDuration
            logger.debug("[NowPlayingUX] duration preserved source=previousSession duration=\(Int(lastKnownDuration))")
        } else if viewState.video.duration.isFinite && viewState.video.duration > 0 {
            viewState.duration = viewState.video.duration
            lastKnownDuration = viewState.video.duration
            logger.debug("[NowPlayingUX] duration preserved source=videoMetadata duration=\(Int(viewState.video.duration))")
        } else {
            viewState.duration = nil
        }
    }

    private func configureSubtitleSelection(for stream: VideoStream) {
        viewState.captionsEnabled = subtitlePreferenceStore.isEnabled
        if let savedSubtitleID = subtitlePreferenceStore.subtitleID,
           stream.subtitles.contains(where: { $0.id == savedSubtitleID }) {
            viewState.selectedSubtitleID = savedSubtitleID
        } else {
            viewState.selectedSubtitleID = stream.subtitles.first(where: \.isDefault)?.id ?? stream.subtitles.first?.id
        }
        viewState.subtitleErrorMessage = nil
        viewState.activeCaptionText = nil
        subtitleCues = []
    }

    private func loadSelectedSubtitleIfNeeded(reason: String) async {
        subtitleGeneration += 1
        let generation = subtitleGeneration
        guard viewState.captionsEnabled,
              let stream = viewState.stream,
              let selectedSubtitleID = viewState.selectedSubtitleID,
              let subtitle = stream.subtitles.first(where: { $0.id == selectedSubtitleID }) else {
            subtitleCues = []
            viewState.activeCaptionText = nil
            viewState.isSubtitleLoading = false
            return
        }

        guard subtitle.format == .webVTT || subtitle.format == .srt else {
            viewState.subtitleErrorMessage = "지원하지 않는 자막 형식입니다."
            viewState.isSubtitleLoading = false
            subtitleCues = []
            return
        }

        viewState.isSubtitleLoading = true
        viewState.subtitleErrorMessage = nil
        let startedAt = Date()
        do {
            let headers = (try? await makeProtectedResourceHeaders()) ?? [:]
            let cues = try await VideoSubtitleLoader.load(subtitle: subtitle, headers: headers)
            guard generation == subtitleGeneration else {
                logger.debug("[VideoSubtitle] stale load ignored generation=\(generation) current=\(subtitleGeneration)")
                return
            }
            subtitleCues = cues
            viewState.isSubtitleLoading = false
            updateActiveCaption(at: viewState.currentTime)
            logger.debug("[VideoSubtitle] loaded language=\(subtitle.languageCode) format=\(subtitle.format.rawValue) cueCount=\(cues.count) elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1000)) reason=\(reason)")
        } catch {
            guard generation == subtitleGeneration else { return }
            subtitleCues = []
            viewState.isSubtitleLoading = false
            viewState.activeCaptionText = nil
            viewState.subtitleErrorMessage = "자막을 불러오지 못했습니다."
            logger.debug("[VideoSubtitle] load failed language=\(subtitle.languageCode) reason=\(error.localizedDescription)")
        }
    }

    private func cancelSubtitleLoading(reason: String) {
        subtitleGeneration += 1
        subtitleCues = []
        viewState.isSubtitleLoading = false
        viewState.activeCaptionText = nil
        logger.debug("[VideoSubtitle] cancelled reason=\(reason) generation=\(subtitleGeneration)")
    }

    private func updateActiveCaption(at time: Double) {
        guard viewState.captionsEnabled,
              !subtitleCues.isEmpty else {
            viewState.activeCaptionText = nil
            return
        }

        let text = subtitleCues.first { cue in
            time >= cue.start && time <= cue.end
        }?.text
        if viewState.activeCaptionText != text {
            viewState.activeCaptionText = text
        }
    }

    private func configureSystemSubtitleIfNeeded(for item: AVPlayerItem) {
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            viewState.hasSystemSubtitleTracks = false
            return
        }

        viewState.hasSystemSubtitleTracks = !group.options.isEmpty
        guard viewState.captionsEnabled else {
            item.select(nil, in: group)
            return
        }

        if viewState.stream?.subtitles.isEmpty == false {
            item.select(nil, in: group)
            return
        }

        let option = group.defaultOption ?? group.options.first
        item.select(option, in: group)
    }

    private func deselectSystemSubtitlesIfNeeded() {
        guard let item = player?.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return
        }
        item.select(nil, in: group)
    }
}

struct VideoSubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

enum VideoSubtitleParser {
    static func parse(_ rawText: String, format: VideoSubtitleFormat) -> [VideoSubtitleCue] {
        switch format {
        case .webVTT:
            return parseBlocks(rawText, timestampSeparator: " --> ")
        case .srt:
            return parseBlocks(rawText, timestampSeparator: " --> ")
        case .unknown:
            return []
        }
    }

    private static func parseBlocks(_ rawText: String, timestampSeparator: String) -> [VideoSubtitleCue] {
        rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap { parseBlock($0, timestampSeparator: timestampSeparator) }
            .filter { $0.end > $0.start && !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
    }

    private static func parseBlock(_ block: String, timestampSeparator: String) -> VideoSubtitleCue? {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("NOTE") && !$0.hasPrefix("WEBVTT") }

        guard let timestampLineIndex = lines.firstIndex(where: { $0.contains(timestampSeparator) }) else {
            return nil
        }

        let timestampLine = lines[timestampLineIndex]
        let parts = timestampLine.components(separatedBy: timestampSeparator)
        guard parts.count >= 2,
              let start = parseTimestamp(parts[0]),
              let end = parseTimestamp(parts[1].components(separatedBy: " ").first ?? parts[1]) else {
            return nil
        }

        let text = lines
            .dropFirst(timestampLineIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return VideoSubtitleCue(start: start, end: end, text: text)
    }

    private static func parseTimestamp(_ rawValue: String) -> Double? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let secondsPart = parts.last ?? ""
        let secondComponents = secondsPart.split(separator: ".", omittingEmptySubsequences: false)
        guard let wholeSeconds = Double(secondComponents.first.map(String.init) ?? "") else {
            return nil
        }
        let fractional = secondComponents.count > 1
            ? Double("0.\(secondComponents[1])") ?? 0
            : 0
        let minutes = Double(parts[parts.count - 2]) ?? 0
        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        return hours * 3600 + minutes * 60 + wholeSeconds + fractional
    }
}

private enum VideoSubtitleLoader {
    static func load(subtitle: VideoSubtitle, headers: [String: String]) async throws -> [VideoSubtitleCue] {
        var request = URLRequest(url: subtitle.url)
        for (field, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return await Task.detached(priority: .utility) {
            let text = String(decoding: data, as: UTF8.self)
            return VideoSubtitleParser.parse(text, format: subtitle.format)
        }.value
    }
}

private struct VideoSubtitlePreferenceStore {
    private enum Key {
        static let enabled = "video.subtitle.enabled"
        static let subtitleID = "video.subtitle.selectedID"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        if userDefaults.object(forKey: Key.enabled) == nil {
            return true
        }
        return userDefaults.bool(forKey: Key.enabled)
    }

    var subtitleID: String? {
        userDefaults.string(forKey: Key.subtitleID)
    }

    func saveEnabled(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Key.enabled)
    }

    func saveSubtitleID(_ subtitleID: String?) {
        if let subtitleID {
            userDefaults.set(subtitleID, forKey: Key.subtitleID)
        } else {
            userDefaults.removeObject(forKey: Key.subtitleID)
        }
    }
}

private enum HLSAuthMode: String, Sendable, CaseIterable {
    case tokenOnly
    case tokenPlusSeSACKey
    case tokenPlusProtectedResourceHeaders
}

private struct HLSHeaderSnapshot: Sendable {
    let headerNames: [String]
    let hasAuthorization: Bool
    let hasSeSACKey: Bool
    let hasLegacySeSACKey: Bool
    let hasContentType: Bool
    let apiKeyLength: Int?
    let authorizationExists: Bool

    init(headers: [String: String]) {
        self.headerNames = headers.keys.sorted()
        self.hasAuthorization = headers[HTTPHeaderField.authorization]?.isEmpty == false
        self.hasSeSACKey = headers[HTTPHeaderField.sesacKey]?.isEmpty == false
        self.hasLegacySeSACKey = headers[HLSPlaybackHeaderOptions.legacySeSACKeyHeaderField]?.isEmpty == false
        self.hasContentType = headers[HTTPHeaderField.contentType]?.isEmpty == false
        self.apiKeyLength = headers[HTTPHeaderField.sesacKey]?.count
            ?? headers[HLSPlaybackHeaderOptions.legacySeSACKeyHeaderField]?.count
        self.authorizationExists = self.hasAuthorization
    }
}

#if DEBUG
private enum HLSAuthDebugLogger {
    private static let logger = Logger(category: "HLSAuthDebug")

    static func logComparison(imageHeaders: [String: String], hlsHeaders: [String: String]) {
        let image = HLSHeaderSnapshot(headers: imageHeaders)
        let hls = HLSHeaderSnapshot(headers: hlsHeaders)
        logger.debug(
            "[HLSAuthDebug] compare image/protected-resource headers vs HLS headers imageAuthHasAuthorization=\(image.hasAuthorization) imageAuthHasSeSACKey=\(image.hasSeSACKey) imageAuthHeaderNames=\(image.headerNames.joined(separator: ",")) hlsAuthHasAuthorization=\(hls.hasAuthorization) hlsAuthHasSeSACKey=\(hls.hasSeSACKey) hlsAuthHeaderNames=\(hls.headerNames.joined(separator: ",")) apiKeyLengthMatches=\(image.apiKeyLength == hls.apiKeyLength) authorizationExistsMatches=\(image.authorizationExists == hls.authorizationExists)"
        )
    }
}
#endif

private enum HLSPlaybackHeaderOptions {
    static let legacySeSACKeyHeaderField = "SeSACKey"
    private static let avURLAssetHTTPHeaderFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"

    static func assetOptions(headers: [String: String]) -> [String: Any] {
        [
            avURLAssetHTTPHeaderFieldsKey: headers
        ]
    }

    static func applyHeaders(
        to request: inout URLRequest,
        authMode: HLSAuthMode,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) {
        request.setValue(nil, forHTTPHeaderField: HTTPHeaderField.authorization)
        request.setValue(nil, forHTTPHeaderField: HTTPHeaderField.contentType)
        request.setValue(nil, forHTTPHeaderField: HTTPHeaderField.sesacKey)
        request.setValue(nil, forHTTPHeaderField: legacySeSACKeyHeaderField)

        switch authMode {
        case .tokenOnly:
            return
        case .tokenPlusSeSACKey:
            request.setValue(seSACKey, forHTTPHeaderField: legacySeSACKeyHeaderField)
        case .tokenPlusProtectedResourceHeaders:
            for (field, value) in protectedResourceHeaders where field != HTTPHeaderField.contentType {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
    }

    static func headerSnapshot(authMode: HLSAuthMode, protectedResourceHeaders: [String: String]) -> HLSHeaderSnapshot {
        switch authMode {
        case .tokenOnly:
            return HLSHeaderSnapshot(headers: [:])
        case .tokenPlusSeSACKey:
            return HLSHeaderSnapshot(headers: [legacySeSACKeyHeaderField: "present"])
        case .tokenPlusProtectedResourceHeaders:
            return HLSHeaderSnapshot(headers: protectedResourceHeaders)
        }
    }
}

private enum HLSProbeClassification: String, Sendable {
    case hlsPlayable
    case playableMasterPlaylist
    case playableMediaPlaylist
    case tokenExpired
    case unauthorized
    case sesacKeyInvalid
    case hlsRequiresServiceHeader
    case hlsUnauthorizedWithPartialHeaders
    case hlsUnauthorizedEvenWithProtectedHeaders
    case serverReturnedJson
    case fileMissing
    case invalidURL
    case networkError
    case unknown
}

private extension HLSProbeClassification {
    var isTerminalHLSAuthFailure: Bool {
        switch self {
        case .hlsRequiresServiceHeader, .hlsUnauthorizedWithPartialHeaders, .hlsUnauthorizedEvenWithProtectedHeaders:
            return true
        default:
            return false
        }
    }
}

private struct HLSProbeCandidate: Sendable {
    let requestedVideoID: String
    let responseVideoID: String
    let quality: String
    let rawPath: String
    let url: URL
    let authMode: HLSAuthMode

    var candidateName: String {
        quality == "auto" ? "stream_url" : quality
    }
}

private struct HLSProbeResult: Sendable {
    let candidate: HLSProbeCandidate
    let statusCode: Int
    let contentType: String?
    let bodyType: String
    let bodyPrefix: String?
    let classification: HLSProbeClassification
    let hasExtM3U: Bool
    let hasStreamInf: Bool
    let hasExtInf: Bool
    let uriLines: [String]
    let mediaURIs: [String]
    let tokenLengthPreserved: Bool
    let headerSnapshot: HLSHeaderSnapshot

    var isPlayablePlaylist: Bool {
        classification == .hlsPlayable || classification == .playableMasterPlaylist || classification == .playableMediaPlaylist
    }
}

private struct PlaybackCandidate: Sendable {
    let quality: String
    let url: URL
    let authMode: HLSAuthMode
}

private struct HLSProbeFailure: Error, LocalizedError {
    let results: [HLSProbeResult]

    var detailReason: String {
        guard let lastResult = results.last else {
            return "hlsTokenPlaybackFailed(status=-1)"
        }

        if lastResult.classification.isTerminalHLSAuthFailure {
            return "\(lastResult.classification.rawValue)(status=\(lastResult.statusCode))"
        }

        return "hlsTokenPlaybackFailed(status=\(lastResult.statusCode))"
    }

    var shouldRefreshStreamOnce: Bool {
        results.contains { $0.classification == .hlsUnauthorizedEvenWithProtectedHeaders }
    }

    var refreshRetryReason: String {
        if let result = results.last(where: { $0.classification == .hlsUnauthorizedEvenWithProtectedHeaders }) {
            return "\(result.classification.rawValue)(status=\(result.statusCode))"
        }
        return "hlsTerminalAuthFailure"
    }

    var errorDescription: String? {
        detailReason
    }
}

private struct HLSProbeRawResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

private final class HLSProbeClient: @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = nil
        configuration.protocolClasses = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    func fetchPlaylistHeadOrPrefix(
        url: URL,
        authMode: HLSAuthMode,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async throws -> HLSProbeRawResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        HLSPlaybackHeaderOptions.applyHeaders(
            to: &request,
            authMode: authMode,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
        request.setValue("bytes=0-4095", forHTTPHeaderField: HTTPHeaderField.range)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.transport
        }
        return HLSProbeRawResponse(data: data, response: httpResponse)
    }
}

private enum HLSProbeService {
    private static let logger = Logger(category: "HLSProbe")
    private static let client = HLSProbeClient()
#if DEBUG
    private static let isLegacyComparisonDiagnosticsEnabled = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
#else
    private static let isLegacyComparisonDiagnosticsEnabled = false
#endif

    static func resolvePlaybackCandidate(
        selectedQuality: String,
        stream: VideoStream,
        requestedVideoID: String,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async throws -> PlaybackCandidate {
        var results: [HLSProbeResult] = []
        let probeEntries = qualityProbeOrder(selectedQuality: selectedQuality, stream: stream)
        if let masterEntry = probeEntries.first {
            await fetchLegacyComparisonDiagnostics(
                selectedQuality: masterEntry.quality,
                rawPath: masterEntry.rawPath,
                url: masterEntry.url,
                requestedVideoID: requestedVideoID,
                responseVideoID: stream.videoId,
                seSACKey: seSACKey,
                protectedResourceHeaders: protectedResourceHeaders
            )
        }

#if DEBUG
        HLSAuthDebugLogger.logComparison(
            imageHeaders: protectedResourceHeaders,
            hlsHeaders: protectedResourceHeaders
        )
#endif

        for (quality, url, rawPath) in probeEntries {
            let candidate = HLSProbeCandidate(
                requestedVideoID: requestedVideoID,
                responseVideoID: stream.videoId,
                quality: quality,
                rawPath: rawPath,
                url: url,
                authMode: .tokenPlusProtectedResourceHeaders
            )
            let result = await fetchPlaylist(
                candidate: candidate,
                seSACKey: seSACKey,
                protectedResourceHeaders: protectedResourceHeaders
            )
            results.append(result)
            if result.isPlayablePlaylist {
                if quality == "auto",
                   selectedQuality == "auto",
                   probeEntries.count > 1,
                   shouldPreferVariantPlaylist(over: result) {
                    logger.warning(
                        "[HLSDiagnostics] masterPlaylistSkipped reason=subtitleURIWithoutToken fallback=variantPlaylist"
                    )
                    continue
                }
                if selectedQuality != "auto", quality == "auto", probeEntries.count > 1 {
                    continue
                }
                return PlaybackCandidate(
                    quality: quality,
                    url: url,
                    authMode: .tokenPlusProtectedResourceHeaders
                )
            }
            if result.classification.isTerminalHLSAuthFailure {
                throw HLSProbeFailure(results: results)
            }
        }

        throw HLSProbeFailure(results: results)
    }

    private static func shouldPreferVariantPlaylist(over result: HLSProbeResult) -> Bool {
        result.hasStreamInf
            && result.mediaURIs.contains {
                isSubtitleURI($0) && !VideoURLLogDescriptor(rawValue: $0).queryExists
            }
    }

    private static func fetchLegacyComparisonDiagnostics(
        selectedQuality: String,
        rawPath: String,
        url: URL,
        requestedVideoID: String,
        responseVideoID: String,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async {
        guard isLegacyComparisonDiagnosticsEnabled else { return }

        let tokenOnlyCandidate = HLSProbeCandidate(
            requestedVideoID: requestedVideoID,
            responseVideoID: responseVideoID,
            quality: selectedQuality,
            rawPath: rawPath,
            url: url,
            authMode: .tokenOnly
        )
        _ = await fetchPlaylist(
            candidate: tokenOnlyCandidate,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )

        let partialHeaderCandidate = HLSProbeCandidate(
            requestedVideoID: requestedVideoID,
            responseVideoID: responseVideoID,
            quality: selectedQuality,
            rawPath: rawPath,
            url: url,
            authMode: .tokenPlusSeSACKey
        )
        _ = await fetchPlaylist(
            candidate: partialHeaderCandidate,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
    }

    private static func qualityProbeOrder(
        selectedQuality: String,
        stream: VideoStream
    ) -> [(quality: String, url: URL, rawPath: String)] {
        if selectedQuality != "auto",
           let quality = stream.qualities.first(where: { $0.quality == selectedQuality }) {
            return [
                ("auto", stream.streamURL, stream.streamURLPath),
                (quality.quality, quality.url, quality.urlPath)
            ]
        }

        let available = Dictionary(uniqueKeysWithValues: stream.qualities.map { ($0.quality, $0) })
        var result: [(String, URL, String)] = [("auto", stream.streamURL, stream.streamURLPath)]
        for quality in ["1080p", "720p", "480p"] {
            if let streamQuality = available[quality] {
                result.append((quality, streamQuality.url, streamQuality.urlPath))
            }
        }
        return result
    }

    static func fetchPlaylist(
        candidate: HLSProbeCandidate,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async -> HLSProbeResult {
        let rawDescriptor = VideoURLLogDescriptor(rawValue: candidate.rawPath)
        let descriptor = VideoURLLogDescriptor(url: candidate.url)
        let pathNormalization = HLSStreamPathNormalizer.normalization(for: rawDescriptor.path)
        let tokenLengthPreserved = rawDescriptor.tokenValueLength == 0 || rawDescriptor.tokenValueLength == descriptor.tokenValueLength
        let headerSnapshot = HLSPlaybackHeaderOptions.headerSnapshot(
            authMode: candidate.authMode,
            protectedResourceHeaders: protectedResourceHeaders
        )

        guard candidate.url.scheme?.isEmpty == false,
              candidate.url.host?.isEmpty == false else {
            return HLSProbeResult(
                candidate: candidate,
                statusCode: -1,
                contentType: nil,
                bodyType: "invalidURL",
                bodyPrefix: nil,
                classification: .invalidURL,
                hasExtM3U: false,
                hasStreamInf: false,
                hasExtInf: false,
                uriLines: [],
                mediaURIs: [],
                tokenLengthPreserved: tokenLengthPreserved,
                headerSnapshot: headerSnapshot
            )
        }

        do {
            let rawResponse = try await client.fetchPlaylistHeadOrPrefix(
                url: candidate.url,
                authMode: candidate.authMode,
                seSACKey: seSACKey,
                protectedResourceHeaders: protectedResourceHeaders
            )
            let body = String(data: rawResponse.data.prefix(4096), encoding: .utf8) ?? "<non-utf8>"
            let contentType = rawResponse.response.value(forHTTPHeaderField: HTTPHeaderField.contentType)
            let bodyType = bodyType(body: body, contentType: contentType)
            let hasExtM3U = body.contains("#EXTM3U")
            let hasStreamInf = body.contains("#EXT-X-STREAM-INF")
            let hasExtInf = body.contains("#EXTINF")
            let classification = classify(
                statusCode: rawResponse.response.statusCode,
                contentType: contentType,
                body: body,
                bodyType: bodyType,
                hasExtM3U: hasExtM3U,
                hasStreamInf: hasStreamInf,
                hasExtInf: hasExtInf,
                authMode: candidate.authMode
            )
            let result = HLSProbeResult(
                candidate: candidate,
                statusCode: rawResponse.response.statusCode,
                contentType: contentType,
                bodyType: bodyType,
                bodyPrefix: sanitizedBodyPrefix(from: body),
                classification: classification,
                hasExtM3U: hasExtM3U,
                hasStreamInf: hasStreamInf,
                hasExtInf: hasExtInf,
                uriLines: parseURILines(from: body),
                mediaURIs: parseAttributeURIs(from: body),
                tokenLengthPreserved: tokenLengthPreserved,
                headerSnapshot: headerSnapshot
            )
            logger.debug(
                "[HLSProbeRequest] videoId=\(candidate.requestedVideoID) responseVideoId=\(candidate.responseVideoID) selectedQuality=\(candidate.quality) originalPath=\(pathNormalization.originalPath) normalizedPath=\(descriptor.path) pathNormalization=\(pathNormalization.action.rawValue) resolvedScheme=\(descriptor.scheme) resolvedHost=\(descriptor.host) resolvedPort=\(descriptor.port) resolvedPath=\(descriptor.path) queryKeys=\(descriptor.queryKeys) tokenLengthPreserved=\(tokenLengthPreserved) authMode=\(candidate.authMode.rawValue) usesAPIClient=false headerAuthorization=\(headerSnapshot.hasAuthorization) headerSeSACKey=\(headerSnapshot.hasSeSACKey || headerSnapshot.hasLegacySeSACKey) headerContentType=\(headerSnapshot.hasContentType) session=ephemeral"
            )
            logger.debug(
                "[HLSProbe] videoId=\(candidate.requestedVideoID) responseVideoId=\(candidate.responseVideoID) selectedQuality=\(candidate.quality) candidate=\(candidate.candidateName) authMode=\(candidate.authMode.rawValue) originalPath=\(pathNormalization.originalPath) normalizedPath=\(descriptor.path) pathNormalization=\(pathNormalization.action.rawValue) resolvedHost=\(descriptor.host) resolvedPort=\(descriptor.port) resolvedPath=\(descriptor.path) queryKeys=\(descriptor.queryKeys) tokenLengthPreserved=\(tokenLengthPreserved) status=\(result.statusCode) contentType=\(result.contentType ?? "nil") bodyType=\(result.bodyType) classification=\(result.classification.rawValue) hasExtM3U=\(result.hasExtM3U) hasStreamInf=\(result.hasStreamInf) hasExtInf=\(result.hasExtInf) uriCount=\(result.uriLines.count) responseMessage=\(result.bodyPrefix ?? "nil")"
            )
            if result.statusCode == 420 || result.statusCode == 444 {
                logger.warning(
                    "[HLSProbe] status=\(result.statusCode) videoId=\(candidate.requestedVideoID) responseVideoId=\(candidate.responseVideoID) selectedQuality=\(candidate.quality) originalPath=\(pathNormalization.originalPath) normalizedPath=\(descriptor.path) pathNormalization=\(pathNormalization.action.rawValue) resolvedHost=\(descriptor.host) resolvedPort=\(descriptor.port) resolvedPath=\(descriptor.path) queryKeys=\(descriptor.queryKeys) tokenLengthPreserved=\(tokenLengthPreserved) responseMessage=\(result.bodyPrefix ?? "nil") classification=\(result.classification.rawValue) authMode=\(candidate.authMode.rawValue) headerAuthorization=\(headerSnapshot.hasAuthorization) headerSeSACKey=\(headerSnapshot.hasSeSACKey || headerSnapshot.hasLegacySeSACKey) headerContentType=\(headerSnapshot.hasContentType) usesAPIClient=false"
                )
            }
            logTokenlessInternalURIsIfNeeded(result)
            return result
        } catch {
            let nsError = error as NSError
            logger.debug(
                "[HLSProbeRequest] videoId=\(candidate.requestedVideoID) responseVideoId=\(candidate.responseVideoID) selectedQuality=\(candidate.quality) originalPath=\(pathNormalization.originalPath) normalizedPath=\(descriptor.path) pathNormalization=\(pathNormalization.action.rawValue) resolvedScheme=\(descriptor.scheme) resolvedHost=\(descriptor.host) resolvedPort=\(descriptor.port) resolvedPath=\(descriptor.path) queryKeys=\(descriptor.queryKeys) tokenLengthPreserved=\(tokenLengthPreserved) authMode=\(candidate.authMode.rawValue) usesAPIClient=false headerAuthorization=\(headerSnapshot.hasAuthorization) headerSeSACKey=\(headerSnapshot.hasSeSACKey || headerSnapshot.hasLegacySeSACKey) headerContentType=\(headerSnapshot.hasContentType) session=ephemeral"
            )
            logger.warning(
                "[HLSProbe] videoId=\(candidate.requestedVideoID) responseVideoId=\(candidate.responseVideoID) selectedQuality=\(candidate.quality) candidate=\(candidate.candidateName) authMode=\(candidate.authMode.rawValue) failed domain=\(nsError.domain) code=\(nsError.code) originalPath=\(pathNormalization.originalPath) normalizedPath=\(descriptor.path) pathNormalization=\(pathNormalization.action.rawValue) resolvedHost=\(descriptor.host) resolvedPort=\(descriptor.port) resolvedPath=\(descriptor.path) queryExists=\(descriptor.queryExists) queryKeys=\(descriptor.queryKeys) tokenLengthPreserved=\(tokenLengthPreserved)"
            )
            return HLSProbeResult(
                candidate: candidate,
                statusCode: nsError.code,
                contentType: nil,
                bodyType: "transport",
                bodyPrefix: "",
                classification: .networkError,
                hasExtM3U: false,
                hasStreamInf: false,
                hasExtInf: false,
                uriLines: [],
                mediaURIs: [],
                tokenLengthPreserved: tokenLengthPreserved,
                headerSnapshot: headerSnapshot
            )
        }
    }

    private static func parseURILines(from body: String) -> [String] {
        body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func parseAttributeURIs(from body: String) -> [String] {
        body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("#EXT-X-MEDIA") || $0.hasPrefix("#EXT-X-I-FRAME-STREAM-INF") }
            .compactMap(attributeURI)
    }

    private static func attributeURI(from line: String) -> String? {
        guard let range = line.range(of: #"URI="([^"]+)""#, options: .regularExpression) else {
            return nil
        }

        let matched = String(line[range])
        guard matched.count > 6 else { return nil }
        return String(matched.dropFirst(5).dropLast())
    }

    private static func logTokenlessInternalURIsIfNeeded(_ result: HLSProbeResult) {
        for uri in result.mediaURIs where isSubtitleURI(uri) && !VideoURLLogDescriptor(rawValue: uri).queryExists {
            logger.warning(
                "[HLSDiagnostics] subtitleURIWithoutToken uri=\(maskedURI(uri)) reason=avplayer_internal_request_will_not_preserve_master_query"
            )
        }

        if result.hasStreamInf,
           result.uriLines.contains(where: { $0.hasSuffix(".m3u8") && !VideoURLLogDescriptor(rawValue: $0).queryExists }) {
            logger.warning(
                "[HLSDiagnostics] variantURIWithoutToken reason=avplayer_internal_request_will_not_preserve_master_query"
            )
        }
    }

    private static func isSubtitleURI(_ uri: String) -> Bool {
        let lowercasedURI = uri.lowercased()
        return lowercasedURI.hasSuffix(".vtt")
            || lowercasedURI.contains(".vtt?")
            || lowercasedURI.contains("subtitle")
            || lowercasedURI.contains("subtitles")
    }

    private static func maskedURI(_ uri: String) -> String {
        let descriptor = VideoURLLogDescriptor(rawValue: uri)
        if descriptor.queryExists {
            return "\(descriptor.path)?<redacted>"
        }
        return descriptor.path
    }

    private static func bodyType(body: String, contentType: String?) -> String {
        let normalizedContentType = contentType?.lowercased() ?? ""
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedContentType.contains("json") || trimmedBody.hasPrefix("{") || trimmedBody.hasPrefix("[") {
            return "json"
        }

        if normalizedContentType.contains("html") || trimmedBody.lowercased().hasPrefix("<!doctype html") || trimmedBody.lowercased().hasPrefix("<html") {
            return "html"
        }

        if trimmedBody.contains("#EXTM3U") {
            return "playlist"
        }

        if trimmedBody.isEmpty {
            return "empty"
        }

        return "text"
    }

    private static func classify(
        statusCode: Int,
        contentType: String?,
        body: String,
        bodyType: String,
        hasExtM3U: Bool,
        hasStreamInf: Bool,
        hasExtInf: Bool,
        authMode: HLSAuthMode
    ) -> HLSProbeClassification {
        let normalizedContentType = contentType?.lowercased() ?? ""
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = (jsonMessage(from: body) ?? trimmedBody).lowercased()

        if (200..<300).contains(statusCode), hasExtM3U {
            return .hlsPlayable
        }

        if statusCode == 200, bodyType == "json" {
            return .serverReturnedJson
        }

        if statusCode == 401 {
            return .unauthorized
        }

        if statusCode == 418 || statusCode == 419 {
            return .tokenExpired
        }

        if statusCode == 404 {
            return .fileMissing
        }

        if statusCode == 420 {
            if isHLSServiceGuardMessage(message) {
                return .hlsRequiresServiceHeader
            }
            if message.contains("sesackey") || message.contains("sesac key") || message.contains("api key") || message.contains("key") {
                return .sesacKeyInvalid
            }
        }

        if statusCode == 444 {
            switch authMode {
            case .tokenPlusSeSACKey:
                return .hlsUnauthorizedWithPartialHeaders
            case .tokenPlusProtectedResourceHeaders:
                return .hlsUnauthorizedEvenWithProtectedHeaders
            case .tokenOnly:
                return .unauthorized
            }
        }

        if bodyType == "json" || normalizedContentType.contains("json") {
            return .serverReturnedJson
        }

        if (200..<300).contains(statusCode),
           (isHLSContentType(normalizedContentType) || hasExtInf) {
            return hasExtM3U ? .playableMediaPlaylist : .unknown
        }

        return .unknown
    }

    private static func isHLSServiceGuardMessage(_ message: String) -> Bool {
        message.contains("this service") && message.contains("only")
    }

    private static func isHLSContentType(_ contentType: String) -> Bool {
        contentType.contains("application/vnd.apple.mpegurl")
            || contentType.contains("application/x-mpegurl")
            || contentType.contains("audio/mpegurl")
    }

    private static func sanitizedBodyPrefix(from body: String) -> String? {
        if let message = jsonMessage(from: body) {
            return "message=\(SensitiveLogRedactor.redact(message))"
        }

        let prefix = redacted(bodyPrefix: String(body.prefix(120)))
        return prefix.isEmpty ? nil : prefix
    }

    private static func jsonMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return nil
        }

        return message
    }

    private static func redacted(bodyPrefix: String) -> String {
        let tokenPattern = #"(?i)(token=)[^\s&"]+"#
        let tokenRedacted = bodyPrefix.replacingOccurrences(
            of: tokenPattern,
            with: "$1<redacted>",
            options: .regularExpression
        )
        return SensitiveLogRedactor.redact(tokenRedacted)
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

#if DEBUG
private enum HLSDebugDiagnosticsOptions {
    static let isEnabled = ProcessInfo.processInfo.environment["PIKKO_HLS_DEBUG_DIAGNOSTICS"] == "1"
}

private enum HLSPlaylistDiagnostics {
    private static let logger = Logger(category: "HLSDiagnostics")

    static func run(stream: VideoStream, seSACKey: String, protectedResourceHeaders: [String: String]) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        Task.detached(priority: .utility) {
            await diagnose(
                stream: stream,
                seSACKey: seSACKey,
                protectedResourceHeaders: protectedResourceHeaders
            )
        }
    }

    private static func diagnose(
        stream: VideoStream,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async {
        let qualityPriority = ["720p": 0, "480p": 1, "1080p": 2]
        let qualityEntries = stream.qualities
            .sorted {
                let lhsPriority = qualityPriority[$0.quality] ?? Int.max
                let rhsPriority = qualityPriority[$1.quality] ?? Int.max
                if lhsPriority == rhsPriority {
                    return $0.quality < $1.quality
                }
                return lhsPriority < rhsPriority
            }
            .map { ($0.quality, $0.url, $0.urlPath) }
        let entries = [("stream_url", stream.streamURL, stream.streamURLPath)] + qualityEntries
        for entry in entries {
            let tokenPlusSeSACKeyReport = await HLSProbeService.fetchPlaylist(
                candidate: HLSProbeCandidate(
                    requestedVideoID: stream.videoId,
                    responseVideoID: stream.videoId,
                    quality: entry.0 == "stream_url" ? "auto" : entry.0,
                    rawPath: entry.2,
                    url: entry.1,
                    authMode: .tokenPlusProtectedResourceHeaders
                ),
                seSACKey: seSACKey,
                protectedResourceHeaders: protectedResourceHeaders
            )

            logPlaylistURIs(name: entry.0, report: tokenPlusSeSACKeyReport)
            await probeSubtitleIfNeeded(
                playlistName: entry.0,
                playlistURL: entry.1,
                mediaURIs: tokenPlusSeSACKeyReport.mediaURIs,
                seSACKey: seSACKey,
                protectedResourceHeaders: protectedResourceHeaders
            )
            if tokenPlusSeSACKeyReport.hasExtInf {
                await probeFirstSegment(
                    playlistName: entry.0,
                    playlistURL: entry.1,
                    uriLines: tokenPlusSeSACKeyReport.uriLines,
                    seSACKey: seSACKey,
                    protectedResourceHeaders: protectedResourceHeaders
                )
            }
        }
    }

    private static func logPlaylistURIs(name: String, report: HLSProbeResult) {
        for (index, uri) in report.mediaURIs.prefix(5).enumerated() {
            let descriptor = VideoURLLogDescriptor(rawValue: uri)
            logger.debug(
                "[HLSDiagnostics] mediaURI[\(index)]=\(maskedURI(uri)) queryExists=\(descriptor.queryExists)"
            )
        }

        for (index, uri) in report.uriLines.prefix(5).enumerated() {
            let descriptor = VideoURLLogDescriptor(rawValue: uri)
            logger.debug(
                "[HLSDiagnostics] uri[\(index)]=\(maskedURI(uri)) queryExists=\(descriptor.queryExists)"
            )
        }

        if report.hasStreamInf,
           report.uriLines.contains(where: { !VideoURLLogDescriptor(rawValue: $0).queryExists }) {
            logger.warning(
                "[HLSDiagnostics] \(name) variant uri has no query token. AVPlayer may request child playlist without token."
            )
        }

        if report.hasExtInf,
           report.uriLines.contains(where: { !VideoURLLogDescriptor(rawValue: $0).queryExists }) {
            logger.warning(
                "[HLSDiagnostics] segment uri has no query token. Server may reject segment request if token is required."
            )
        }
    }

    private static func probeSubtitleIfNeeded(
        playlistName: String,
        playlistURL: URL,
        mediaURIs: [String],
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async {
        guard let subtitleURI = mediaURIs.first(where: isSubtitleURI),
              let subtitleURL = URL(string: subtitleURI, relativeTo: playlistURL)?.absoluteURL else {
            return
        }

        let report = await probeTextResource(
            url: subtitleURL,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
        let descriptor = VideoURLLogDescriptor(url: subtitleURL)
        logger.debug(
            "[HLSDiagnostics] subtitle probe playlist=\(playlistName) status=\(report.statusCode) path=\(descriptor.path) queryExists=\(descriptor.queryExists) contentType=\(report.contentType ?? "nil") firstLine=\(report.firstLine)"
        )
        if !descriptor.queryExists {
            logger.warning(
                "[HLSDiagnostics] subtitleURIWithoutToken uri=\(maskedURI(subtitleURI)) reason=avplayer_internal_request_will_not_preserve_master_query"
            )
        }
        if report.statusCode >= 200,
           report.statusCode < 300,
           report.firstLine.uppercased() != "WEBVTT" {
            logger.warning(
                "[HLSDiagnostics] subtitleInvalidVTT path=\(descriptor.path) reason=first_line_must_be_WEBVTT"
            )
        }
    }

    private static func probeFirstSegment(
        playlistName: String,
        playlistURL: URL,
        uriLines: [String],
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async {
        guard let segmentURI = uriLines.first(where: { !$0.hasSuffix(".m3u8") }),
              let originalURL = URL(string: segmentURI, relativeTo: playlistURL)?.absoluteURL else {
            return
        }

        let originalStatus = await probeSegment(
            url: originalURL,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
        let originalDescriptor = VideoURLLogDescriptor(url: originalURL)
        logger.debug(
            "[HLSDiagnostics] segment probe original playlist=\(playlistName) status=\(originalStatus) path=\(originalDescriptor.path) queryExists=\(originalDescriptor.queryExists)"
        )

        let queryCopiedURL = copyQueryIfNeeded(to: originalURL, from: playlistURL)
        guard queryCopiedURL.absoluteString != originalURL.absoluteString else {
            return
        }

        let copiedStatus = await probeSegment(
            url: queryCopiedURL,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
        let copiedDescriptor = VideoURLLogDescriptor(url: queryCopiedURL)
        logger.debug(
            "[HLSDiagnostics] segment probe queryCopied playlist=\(playlistName) status=\(copiedStatus) path=\(copiedDescriptor.path) queryExists=\(copiedDescriptor.queryExists)"
        )

        if (originalStatus == 401 || originalStatus == 403 || originalStatus == 404),
           copiedStatus >= 200,
           copiedStatus < 300 {
            logger.warning(
                "[HLSDiagnostics] segment requires query token. Server playlist does not include token on segment URI. AVPlayer cannot append token automatically."
            )
        }
    }

    private static func probeSegment(
        url: URL,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        HLSPlaybackHeaderOptions.applyHeaders(
            to: &request,
            authMode: .tokenPlusProtectedResourceHeaders,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
        request.setValue("bytes=0-1", forHTTPHeaderField: HTTPHeaderField.range)

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpAdditionalHeaders = nil
            configuration.protocolClasses = nil
            let session = URLSession(configuration: configuration)
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode ?? -1
        } catch {
            let nsError = error as NSError
            logger.warning(
                "[HLSDiagnostics] segment probe failed domain=\(nsError.domain) code=\(nsError.code) path=\(VideoURLLogDescriptor(url: url).path)"
            )
            return -1
        }
    }

    private static func probeTextResource(
        url: URL,
        seSACKey: String,
        protectedResourceHeaders: [String: String]
    ) async -> (statusCode: Int, contentType: String?, firstLine: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        HLSPlaybackHeaderOptions.applyHeaders(
            to: &request,
            authMode: .tokenPlusProtectedResourceHeaders,
            seSACKey: seSACKey,
            protectedResourceHeaders: protectedResourceHeaders
        )
        request.setValue("bytes=0-512", forHTTPHeaderField: HTTPHeaderField.range)

        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpAdditionalHeaders = nil
            configuration.protocolClasses = nil
            let session = URLSession(configuration: configuration)
            let (data, response) = try await session.data(for: request)
            let firstLine = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? "<empty>"
            let httpResponse = response as? HTTPURLResponse
            return (
                httpResponse?.statusCode ?? -1,
                httpResponse?.value(forHTTPHeaderField: HTTPHeaderField.contentType),
                firstLine
            )
        } catch {
            let nsError = error as NSError
            logger.warning(
                "[HLSDiagnostics] text probe failed domain=\(nsError.domain) code=\(nsError.code) path=\(VideoURLLogDescriptor(url: url).path)"
            )
            return (-1, nil, "<error>")
        }
    }

    private static func copyQueryIfNeeded(to url: URL, from sourceURL: URL) -> URL {
        guard !VideoURLLogDescriptor(url: url).queryExists,
              let sourceComponents = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              let sourceQuery = sourceComponents.percentEncodedQuery,
              !sourceQuery.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.percentEncodedQuery = sourceQuery
        return components.url ?? url
    }

    private static func isSubtitleURI(_ uri: String) -> Bool {
        let lowercasedURI = uri.lowercased()
        return lowercasedURI.hasSuffix(".vtt")
            || lowercasedURI.contains(".vtt?")
            || lowercasedURI.contains("subtitle")
            || lowercasedURI.contains("subtitles")
    }

    private static func maskedURI(_ uri: String) -> String {
        let descriptor = VideoURLLogDescriptor(rawValue: uri)
        if descriptor.queryExists {
            return "\(descriptor.path)?<redacted>"
        }
        return descriptor.path
    }

}
#endif

#if DEBUG
private extension VideoPlayerViewModel {
    func debugSelectedSource(for quality: String, in stream: VideoStream) -> String {
        if quality == "auto" {
            return "response.stream_url"
        }

        guard let index = stream.qualities.firstIndex(where: { $0.quality == quality }) else {
            return "qualities[unknown].stream_url"
        }
        return "qualities[\(index)].stream_url"
    }

    func debugLogPlayerError(_ player: AVPlayer, item: AVPlayerItem?) {
        print("[VideoStreamingDebug] player.status=failed")
        print("[VideoStreamingDebug] player.error=\(String(describing: player.error))")
        if let item {
            print("[VideoStreamingDebug] playerItem.error=\(String(describing: item.error))")
            debugLogAVPlayerItemLogs(item)
        }
    }

    func debugLogPlayerFailure(item: AVPlayerItem, player: AVPlayer?) {
        print("[VideoStreamingDebug] AVPlayerItem.status=failed")
        print("[VideoStreamingDebug] playerItem.error=\(String(describing: item.error))")
        print("[VideoStreamingDebug] player.error=\(String(describing: player?.error))")
        if let failedURL = (item.asset as? AVURLAsset)?.url {
            print("[VideoStreamingDebug] failed item asset url=\(VideoURLLogDescriptor(url: failedURL).redactedAbsoluteString)")
            VideoStreamingDebugLogger.logURLComponents(label: "failedItem.assetURL", url: failedURL)
        }
        debugLogAVPlayerItemLogs(item)
    }

    func debugLogAVPlayerItemLogs(_ item: AVPlayerItem) {
        debugLogAccessLogEvents(for: item)
        debugLogErrorLogEvents(for: item)
    }

    func debugLogAccessLogEvents(for item: AVPlayerItem) {
        guard let events = item.accessLog()?.events,
              !events.isEmpty else {
            print("[VideoStreamingDebug] accessLog.events.count=0")
            return
        }

        print("[VideoStreamingDebug] accessLog.events.count=\(events.count)")
        for (index, event) in events.enumerated() {
            let uri = event.uri ?? "nil"
            let redactedURI = event.uri.map { VideoURLLogDescriptor(rawValue: $0).redactedAbsoluteString } ?? "nil"
            print(
                "[VideoStreamingDebug] accessLog.events[\(index)] uri=\(redactedURI) indicatedBitrate=\(event.indicatedBitrate) observedBitrate=\(event.observedBitrate) segmentsDownloadedDuration=\(event.segmentsDownloadedDuration) durationWatched=\(event.durationWatched) numberOfStalls=\(event.numberOfStalls) numberOfMediaRequests=\(event.numberOfMediaRequests) serverAddress=\(event.serverAddress ?? "nil") playbackSessionID=\(event.playbackSessionID ?? "nil")"
            )
            if uri != "nil" {
                VideoStreamingDebugLogger.logURLComponents(label: "accessLog.events[\(index)].uri", rawValue: uri)
            }
        }
    }

    func debugLogErrorLogEvents(for item: AVPlayerItem) {
        guard let events = item.errorLog()?.events,
              !events.isEmpty else {
            print("[VideoStreamingDebug] errorLog.events.count=0")
            return
        }

        print("[VideoStreamingDebug] errorLog.events.count=\(events.count)")
        for (index, event) in events.enumerated() {
            let uri = event.uri ?? "nil"
            let redactedURI = event.uri.map { VideoURLLogDescriptor(rawValue: $0).redactedAbsoluteString } ?? "nil"
            print(
                "[VideoStreamingDebug] errorLog.events[\(index)] uri=\(redactedURI) statusCode=\(event.errorStatusCode) errorDomain=\(event.errorDomain) errorComment=\(event.errorComment ?? "nil") serverAddress=\(event.serverAddress ?? "nil") playbackSessionID=\(event.playbackSessionID ?? "nil")"
            )
            if uri != "nil" {
                VideoStreamingDebugLogger.logURLComponents(label: "errorLog.events[\(index)].uri", rawValue: uri)
            }
        }
    }
}
#endif

private extension VideoPlayerPlaybackState {
    var isFailure: Bool {
        switch self {
        case .failed, .expiredOrUnavailable:
            return true
        default:
            return false
        }
    }
}

private struct ResolvedVideoQuality {
    let identifier: String
    let url: URL
    let rawPath: String
}

struct VideoURLLogDescriptor {
    let scheme: String
    let host: String
    let port: String
    let path: String
    let ext: String
    let queryExists: Bool
    let queryKeys: String
    let queryKeyCount: Int
    let rawQueryLength: Int
    let percentEncodedQueryLength: Int
    let tokenValueLength: Int
    let maskedQuery: String

    init(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawQuery = Self.rawQuery(from: url.absoluteString)
        let percentEncodedQuery = components?.percentEncodedQuery
        self.scheme = url.scheme ?? "nil"
        self.host = url.host ?? "nil"
        self.port = url.port.map(String.init) ?? "nil"
        self.path = components?.percentEncodedPath.removingPercentEncoding ?? url.path
        self.ext = url.pathExtension.isEmpty ? "nil" : url.pathExtension
        self.queryExists = percentEncodedQuery?.isEmpty == false
        self.queryKeys = Self.queryKeys(from: percentEncodedQuery)
        self.queryKeyCount = Self.queryKeyCount(from: components)
        self.rawQueryLength = rawQuery?.count ?? 0
        self.percentEncodedQueryLength = percentEncodedQuery?.count ?? 0
        self.tokenValueLength = Self.queryValueLength(named: "token", from: percentEncodedQuery)
        self.maskedQuery = Self.maskedQuery(from: components)
    }

    init(rawValue: String) {
        if let components = URLComponents(string: rawValue) {
            let rawQuery = Self.rawQuery(from: rawValue)
            let percentEncodedQuery = components.percentEncodedQuery
            self.scheme = components.scheme ?? "nil"
            self.host = components.host ?? "nil"
            self.port = components.port.map(String.init) ?? "nil"
            self.path = components.percentEncodedPath.removingPercentEncoding
                ?? (components.path.isEmpty ? rawValue.components(separatedBy: "?").first ?? rawValue : components.path)
            self.ext = URL(fileURLWithPath: components.path).pathExtension.isEmpty
                ? "nil"
                : URL(fileURLWithPath: components.path).pathExtension
            self.queryExists = percentEncodedQuery?.isEmpty == false
            self.queryKeys = Self.queryKeys(from: percentEncodedQuery)
            self.queryKeyCount = Self.queryKeyCount(from: components)
            self.rawQueryLength = rawQuery?.count ?? 0
            self.percentEncodedQueryLength = percentEncodedQuery?.count ?? 0
            self.tokenValueLength = Self.queryValueLength(named: "token", from: percentEncodedQuery)
            self.maskedQuery = Self.maskedQuery(from: components)
        } else {
            let path = rawValue.components(separatedBy: "?").first ?? rawValue
            let rawQuery = Self.rawQuery(from: rawValue)
            self.scheme = "nil"
            self.host = "nil"
            self.port = "nil"
            self.path = path
            self.ext = (path as NSString).pathExtension.isEmpty ? "nil" : (path as NSString).pathExtension
            self.queryExists = rawValue.contains("?")
            self.queryKeys = Self.queryKeys(from: rawQuery)
            self.queryKeyCount = Self.queryKeyCount(from: rawQuery)
            self.rawQueryLength = rawQuery?.count ?? 0
            self.percentEncodedQueryLength = rawQuery?.count ?? 0
            self.tokenValueLength = Self.queryValueLength(named: "token", from: rawQuery)
            self.maskedQuery = self.queryExists ? "query=<redacted>" : "nil"
        }
    }

    var redactedAbsoluteString: String {
        if scheme == "file" {
            return "file://\(path)"
        }

        var value = "\(scheme)://\(host)"
        if port != "nil" {
            value += ":\(port)"
        }
        value += path
        if queryExists {
            value += "?<redacted>"
        }
        return value
    }

    private static func maskedQuery(from components: URLComponents?) -> String {
        guard let percentEncodedQuery = components?.percentEncodedQuery,
              !percentEncodedQuery.isEmpty else {
            return "nil"
        }

        return percentEncodedQuery
            .split(separator: "&")
            .map { rawPair in
                let rawName = rawPair.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "query"
                let name = rawName.removingPercentEncoding ?? rawName
                return "\(name)=<redacted>"
            }
            .joined(separator: "&")
    }

    private static func queryKeyCount(from components: URLComponents?) -> Int {
        queryKeyCount(from: components?.percentEncodedQuery)
    }

    private static func queryKeyCount(from percentEncodedQuery: String?) -> Int {
        guard let percentEncodedQuery,
              !percentEncodedQuery.isEmpty else { return 0 }

        return percentEncodedQuery.split(separator: "&").count
    }

    private static func queryKeys(from percentEncodedQuery: String?) -> String {
        guard let percentEncodedQuery,
              !percentEncodedQuery.isEmpty else {
            return "nil"
        }

        let keys = percentEncodedQuery
            .split(separator: "&")
            .compactMap { rawPair -> String? in
                let rawName = rawPair.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                let name = rawName.removingPercentEncoding ?? rawName
                return name.isEmpty ? nil : name
            }
        return keys.isEmpty ? "nil" : keys.joined(separator: ",")
    }

    private static func rawQuery(from value: String) -> String? {
        guard let questionMarkIndex = value.firstIndex(of: "?") else {
            return nil
        }

        let queryStart = value.index(after: questionMarkIndex)
        let queryEnd = value[queryStart...].firstIndex(of: "#") ?? value.endIndex
        let query = String(value[queryStart..<queryEnd])
        return query.isEmpty ? nil : query
    }

    private static func queryValueLength(named targetName: String, from percentEncodedQuery: String?) -> Int {
        guard let percentEncodedQuery,
              !percentEncodedQuery.isEmpty else { return 0 }

        for rawPair in percentEncodedQuery.split(separator: "&") {
            let parts = rawPair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawName = parts.first.map(String.init) ?? ""
            let name = rawName.removingPercentEncoding ?? rawName
            guard name == targetName else { continue }
            return parts.count > 1 ? String(parts[1]).count : 0
        }

        return 0
    }
}

private enum VideoPlaybackSelectionError: Error, LocalizedError, Equatable {
    case selectedQualityUnavailable(String)

    var detailReason: String {
        switch self {
        case .selectedQualityUnavailable:
            return "selectedQualityUnavailable"
        }
    }

    var errorDescription: String? {
        switch self {
        case .selectedQualityUnavailable(let quality):
            return "\(quality) 화질을 재생할 수 없습니다."
        }
    }
}
