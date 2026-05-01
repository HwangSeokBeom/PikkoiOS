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
    private let onVideoUpdated: (Video) -> Void
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

    init(
        video: Video,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        appConfiguration: AppConfiguration = AppConfiguration(),
        tokenStore: (any TokenStore)? = nil,
        onVideoUpdated: @escaping (Video) -> Void = { _ in }
    ) {
        self.viewState = VideoPlayerViewState(video: video)
        self.fetchStreamUseCase = fetchStreamUseCase
        self.setLikeUseCase = setLikeUseCase
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
        self.onVideoUpdated = onVideoUpdated
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
            onVideoUpdated: onVideoUpdated
        )
    }

    deinit {
        itemStatusObservation?.invalidate()
        playerStatusObservation?.invalidate()
        playerTimeControlObservation?.invalidate()
    }

    func loadStreamIfNeeded() async {
        guard !hasLoadedInitialStream else { return }
        hasLoadedInitialStream = true
        await loadStream(shouldAutoplay: true, reason: "initialLoad")
    }

    func retryStream() async {
        cancelPendingPlayback(reason: "retry")
        attemptedFallbackQualities.removeAll()
        viewState.effectivePlaybackQuality = nil
        await loadStream(shouldAutoplay: true, reason: "retry")
    }

    func play() {
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
        cancelPendingPlayback(reason: "viewDisappear")
        removeCurrentItemObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerStatusObservation?.invalidate()
        playerStatusObservation = nil
        playerTimeControlObservation?.invalidate()
        playerTimeControlObservation = nil
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
            logger.error("[VideoPlayer] selected quality unavailable quality=\(nextQuality)")
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
            logger.error("[VideoPlayer] failed videoId=\(viewState.video.videoId) reason=playbackFailure")
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
            logger.error("[VideoPlayer] failed videoId=\(viewState.video.videoId) reason=playbackStalledExpired")
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

    func logNavigationRender() {
        logger.debug("[VideoNavigation] render customBackButton=true systemBackButtonHidden=true")
    }

    func handleBackTapped() {
        logger.debug("[VideoNavigation] back tapped source=customButton")
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
            logger.error("[VideoPlayer] invalid empty videoId")
            return
        }

        let requestKey = "\(videoID)|\(viewState.userSelectedQuality)"
        guard activeStreamRequestKey != requestKey else {
            logger.debug("[VideoPlayer] skip duplicate requestStream key=\(requestKey)")
            return
        }
        activeStreamRequestKey = requestKey
        defer { activeStreamRequestKey = nil }

        setPlaybackState(.loadingStream)
        viewState.toastMessage = nil
        viewState.detailReason = nil
        logger.debug("[VideoPlayer] state=loadingStream videoId=\(videoID)")

        do {
            if try await isMissingAuthenticatedSession() {
                logger.warning("[VideoPlayer] stream skipped videoId=\(videoID) reason=missingAuthenticatedSession")
                setPlaybackState(.failed("로그인이 필요합니다."))
                return
            }

            let stream = try await fetchStreamUseCase.execute(videoId: videoID)
            streamIssuedAt = Date()
            viewState.stream = stream
            attemptedFallbackQualities.removeAll()

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
                HLSPlaylistDiagnostics.run(stream: stream)
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
                logger.warning("[VideoPlayer] stream forbidden videoId=\(videoID) keepSession=true")
            }
            logger.error("[VideoPlayer] failed videoId=\(viewState.video.videoId) reason=\(error.localizedDescription)")
        }
    }

    private func setPlaybackState(_ state: VideoPlayerPlaybackState) {
        viewState.playbackState = state
        switch state {
        case .playing:
            logger.debug("[VideoPlayer] state=playing videoId=\(viewState.video.videoId)")
        case .paused:
            logger.debug("[VideoPlayer] state=paused videoId=\(viewState.video.videoId)")
        case .ready:
            logger.debug("[VideoPlayer] state=ready videoId=\(viewState.video.videoId)")
        default:
            break
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
            "[VideoPlayer] prepare item reason=\(reason) requested=\(resolvedQuality.identifier) playbackURLPath=\(descriptor.path) queryExists=\(descriptor.queryExists) queryKeys=\(descriptor.queryKeys) preserveTime=\(seekTime.seconds.isFinite ? seekTime.seconds : 0) generation=\(generation)"
        )
        logger.debug("[VideoPlayer] selected quality=\(resolvedQuality.identifier) urlExists=\(!resolvedQuality.url.absoluteString.isEmpty)")
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
                    "[VideoPlayer] ignore stale item build failure generation=\(generation) current=\(playbackGeneration) quality=\(resolvedQuality.identifier)"
                )
                return
            }

            if let probeFailure = error as? HLSProbeFailure {
                attemptedFallbackQualities.insert(resolvedQuality.identifier)
                viewState.detailReason = probeFailure.detailReason
                setPlaybackState(.failed(userFacingHLSProbeFailureMessage()))
                logger.error("[VideoPlayer] failed videoId=\(viewState.video.videoId) reason=\(probeFailure.detailReason)")
                return
            }

            viewState.detailReason = detailReason(for: error)
            setPlaybackState(.failed(failureMessage ?? userFacingPlaybackFailureMessage(forExplicitQuality: viewState.userSelectedQuality != "auto")))
            logger.error("[VideoPlayer] player error=\(error.localizedDescription)")
            return
        }

        let playbackDescriptor = VideoURLLogDescriptor(url: playbackCandidate.url)
        currentAttemptQuality = playbackCandidate.quality
        currentAttemptAuthMode = playbackCandidate.authMode
        logger.debug(
            "[VideoPlayer] replace item reason=\(reason) quality=\(playbackCandidate.quality) authMode=\(playbackCandidate.authMode.rawValue) assetHeaders=false playbackURLPath=\(playbackDescriptor.path) queryExists=\(playbackDescriptor.queryExists) queryKeys=\(playbackDescriptor.queryKeys) preserveTime=\(seekTime.seconds.isFinite ? seekTime.seconds : 0) generation=\(generation)"
        )

        guard generation == playbackGeneration else {
            logger.debug(
                "[VideoPlayer] ignore stale item build generation=\(generation) current=\(playbackGeneration) quality=\(resolvedQuality.identifier)"
            )
            return
        }

        pendingSeekTime = seekTime.seconds.isFinite && seekTime.seconds > 0 ? seekTime : nil
        pendingResumeAfterReady = shouldResume

        let targetPlayer: AVPlayer
        if let player {
            targetPlayer = player
            installPlayerObserversIfNeeded(for: player)
            player.replaceCurrentItem(with: item)
        } else {
            targetPlayer = AVPlayer(playerItem: item)
            player = targetPlayer
            installPlayerObserversIfNeeded(for: targetPlayer)
        }

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
            detailReason = "forbiddenByStreamServer"
        } else if statusCodes.contains(420) {
            detailReason = "serverServiceMismatch"
        } else {
            detailReason = "playerItemFailed(\(nsError?.code ?? 0))"
        }
        viewState.detailReason = detailReason
        logger.error(
            "[VideoPlayer] item status=failed requested=\(quality) userSelected=\(viewState.userSelectedQuality) error=\(itemError?.localizedDescription ?? "unknown") domain=\(nsError?.domain ?? "nil") code=\(nsError?.code ?? 0) detailReason=\(detailReason)"
        )
        logger.error(
            "[VideoPlayer] item failed quality=\(quality) nsErrorDomain=\(nsError?.domain ?? "nil") nsErrorCode=\(nsError?.code ?? 0) underlying=\(underlyingError.map { "\($0.domain)(\($0.code))" } ?? "nil")"
        )
        logItemErrorLog(for: item)
        logAccessLog(for: item)
        if let playerError = player?.error {
            logger.error("[VideoPlayer] player error=\(playerError.localizedDescription)")
        }

        attemptedFallbackQualities.insert(quality)
        let failedURL = (item.asset as? AVURLAsset)?.url
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
        setPlaybackState(.failed(terminalStreamServerFailure ? streamServerFailureMessage : (failureMessage ?? userFacingPlaybackFailureMessage(forExplicitQuality: viewState.userSelectedQuality != "auto"))))
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
        let playbackCandidate = try await HLSProbeService.resolvePlaybackCandidate(
            selectedQuality: resolvedQuality.identifier,
            stream: stream
        )
        let descriptor = VideoURLLogDescriptor(url: playbackCandidate.url)
        logger.debug(
            "[VideoPlayer] build asset quality=\(playbackCandidate.quality) url=\(descriptor.redactedAbsoluteString) authMode=\(playbackCandidate.authMode.rawValue) assetHeaders=false queryExists=\(descriptor.queryExists) queryKeys=\(descriptor.queryKeys) queryKeyCount=\(descriptor.queryKeyCount) rawQueryLength=\(descriptor.rawQueryLength) percentEncodedQueryLength=\(descriptor.percentEncodedQueryLength) hasAuthorization=false hasSeSACKey=false"
        )
        logATSConfigurationIfNeeded(for: playbackCandidate.url)

        let asset = AVURLAsset(url: playbackCandidate.url)
        return (AVPlayerItem(asset: asset), playbackCandidate)
    }

    private func installPlayerObserversIfNeeded(for player: AVPlayer) {
        playerStatusObservation?.invalidate()
        playerTimeControlObservation?.invalidate()

        playerStatusObservation = player.observe(\.status, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                guard let self else { return }
                if observedPlayer.status == .failed {
                    self.logger.error("[VideoPlayer] player error=\(observedPlayer.error?.localizedDescription ?? "unknown")")
                }
            }
        }

        playerTimeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                guard let self else { return }
                if let error = observedPlayer.error {
                    self.logger.error("[VideoPlayer] player error=\(error.localizedDescription)")
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
                        "[VideoPlayer] ignore stale item status generation=\(generation) current=\(self.playbackGeneration) quality=\(quality)"
                    )
                    return
                }
                switch observedItem.status {
                case .readyToPlay:
                    self.logger.debug(
                        "[VideoPlayer] itemReadyToPlay videoId=\(self.viewState.video.videoId) quality=\(quality) authMode=\(authMode.rawValue)"
                    )
                    self.viewState.effectivePlaybackQuality = quality
                    self.viewState.detailReason = nil
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
                        "[VideoPlayer] item status=unknown videoID=\(self.viewState.video.videoId) quality=\(quality) generation=\(generation)"
                    )
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func removeCurrentItemObserver() {
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
        }
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
}

private enum HLSAuthMode: String, Sendable, CaseIterable {
    case tokenOnly
}

private enum HLSProbeClassification: String, Sendable {
    case playableMasterPlaylist
    case playableMediaPlaylist
    case tokenExpired
    case unauthorized
    case sesacKeyInvalid
    case serviceMismatch
    case serverReturnedJson
    case fileMissing
    case invalidURL
    case networkError
    case unknown
}

private struct HLSProbeCandidate: Sendable {
    let videoID: String
    let quality: String
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

    var isPlayablePlaylist: Bool {
        classification == .playableMasterPlaylist || classification == .playableMediaPlaylist
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

        return "hlsTokenPlaybackFailed(status=\(lastResult.statusCode))"
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

    func fetchPlaylistHeadOrPrefix(url: URL) async throws -> HLSProbeRawResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "SeSACKey")
        request.setValue(nil, forHTTPHeaderField: "SesacKey")
        request.setValue(nil, forHTTPHeaderField: "Content-Type")
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")

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

    static func resolvePlaybackCandidate(
        selectedQuality: String,
        stream: VideoStream
    ) async throws -> PlaybackCandidate {
        var results: [HLSProbeResult] = []
        for (quality, url) in qualityProbeOrder(selectedQuality: selectedQuality, stream: stream) {
            let candidate = HLSProbeCandidate(videoID: stream.videoId, quality: quality, url: url, authMode: .tokenOnly)
            let result = await fetchPlaylist(candidate: candidate)
            results.append(result)
            if result.isPlayablePlaylist {
                return PlaybackCandidate(
                    quality: quality,
                    url: url,
                    authMode: .tokenOnly
                )
            }
        }

        throw HLSProbeFailure(results: results)
    }

    private static func qualityProbeOrder(
        selectedQuality: String,
        stream: VideoStream
    ) -> [(quality: String, url: URL)] {
        if selectedQuality != "auto",
           let quality = stream.qualities.first(where: { $0.quality == selectedQuality }) {
            return [(quality.quality, quality.url)]
        }

        let available = Dictionary(uniqueKeysWithValues: stream.qualities.map { ($0.quality, $0.url) })
        var result: [(String, URL)] = [("auto", stream.streamURL)]
        for quality in ["1080p", "720p", "480p"] {
            if let url = available[quality] {
                result.append((quality, url))
            }
        }
        return result
    }

    static func fetchPlaylist(
        candidate: HLSProbeCandidate
    ) async -> HLSProbeResult {
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
                uriLines: []
            )
        }

        let descriptor = VideoURLLogDescriptor(url: candidate.url)

        do {
            let rawResponse = try await client.fetchPlaylistHeadOrPrefix(url: candidate.url)
            let body = String(data: rawResponse.data.prefix(4096), encoding: .utf8) ?? "<non-utf8>"
            let contentType = rawResponse.response.value(forHTTPHeaderField: "Content-Type")
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
                hasExtInf: hasExtInf
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
                uriLines: parseURILines(from: body)
            )
            logger.debug(
                "[HLSProbeRequest] urlPath=\(descriptor.path) queryKeys=\(descriptor.queryKeys) authMode=\(candidate.authMode.rawValue) usesAPIClient=false headerAuthorization=false headerSeSACKey=false headerContentType=false session=ephemeral"
            )
            logger.debug(
                "[HLSProbe] quality=\(candidate.quality) candidate=\(candidate.candidateName) authMode=\(candidate.authMode.rawValue) status=\(result.statusCode) contentType=\(result.contentType ?? "nil") bodyType=\(result.bodyType) classification=\(result.classification.rawValue) hasExtM3U=\(result.hasExtM3U) hasStreamInf=\(result.hasStreamInf) hasExtInf=\(result.hasExtInf) uriCount=\(result.uriLines.count) bodyPrefix=\(result.bodyPrefix ?? "nil")"
            )
            if result.statusCode == 420 {
                logger.warning(
                    "[HLSProbe] tokenOnly received 420 classification=\(result.classification.rawValue) videoID=\(candidate.videoID) streamURLPath=\(descriptor.path) tokenExists=\(descriptor.queryKeys.split(separator: ",").contains("token")) status=420 responseMessage=\(result.bodyPrefix ?? "nil") headerAuthorization=false headerSeSACKey=false headerContentType=false usesAPIClient=false diagnosis=serverIssuedTokenOrServiceRoutingMismatch"
                )
            }
            return result
        } catch {
            let nsError = error as NSError
            logger.debug(
                "[HLSProbeRequest] urlPath=\(descriptor.path) queryKeys=\(descriptor.queryKeys) authMode=\(candidate.authMode.rawValue) usesAPIClient=false headerAuthorization=false headerSeSACKey=false headerContentType=false session=ephemeral"
            )
            logger.warning(
                "[HLSProbe] quality=\(candidate.quality) candidate=\(candidate.candidateName) authMode=\(candidate.authMode.rawValue) failed domain=\(nsError.domain) code=\(nsError.code) path=\(descriptor.path) queryExists=\(descriptor.queryExists) queryKeys=\(descriptor.queryKeys)"
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
                uriLines: []
            )
        }
    }

    private static func parseURILines(from body: String) -> [String] {
        body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
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
        hasExtInf: Bool
    ) -> HLSProbeClassification {
        let normalizedContentType = contentType?.lowercased() ?? ""
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = (jsonMessage(from: body) ?? trimmedBody).lowercased()

        if (200..<300).contains(statusCode), hasExtM3U {
            return hasStreamInf ? .playableMasterPlaylist : .playableMediaPlaylist
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
            if message.contains("service") {
                return .serviceMismatch
            }
            if message.contains("sesackey") || message.contains("sesac key") || message.contains("api key") || message.contains("key") {
                return .sesacKeyInvalid
            }
        }

        if statusCode == 444 {
            if message.contains("sesac") || message.contains("key") {
                return .sesacKeyInvalid
            }
            return .unauthorized
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

    static func run(stream: VideoStream) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        Task.detached(priority: .utility) {
            await diagnose(stream: stream)
        }
    }

    private static func diagnose(stream: VideoStream) async {
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
            .map { ($0.quality, $0.url) }
        let entries = [("stream_url", stream.streamURL)] + qualityEntries
        for entry in entries {
            let tokenOnlyReport = await HLSProbeService.fetchPlaylist(
                candidate: HLSProbeCandidate(
                    videoID: stream.videoId,
                    quality: entry.0 == "stream_url" ? "auto" : entry.0,
                    url: entry.1,
                    authMode: .tokenOnly
                )
            )

            logPlaylistURIs(name: entry.0, report: tokenOnlyReport)
            if tokenOnlyReport.hasExtInf {
                await probeFirstSegment(playlistName: entry.0, playlistURL: entry.1, uriLines: tokenOnlyReport.uriLines)
            }
        }
    }

    private static func logPlaylistURIs(name: String, report: HLSProbeResult) {
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

    private static func probeFirstSegment(
        playlistName: String,
        playlistURL: URL,
        uriLines: [String]
    ) async {
        guard let segmentURI = uriLines.first(where: { !$0.hasSuffix(".m3u8") }),
              let originalURL = URL(string: segmentURI, relativeTo: playlistURL)?.absoluteURL else {
            return
        }

        let originalStatus = await probeSegment(url: originalURL)
        let originalDescriptor = VideoURLLogDescriptor(url: originalURL)
        logger.debug(
            "[HLSDiagnostics] segment probe original playlist=\(playlistName) status=\(originalStatus) path=\(originalDescriptor.path) queryExists=\(originalDescriptor.queryExists)"
        )

        let queryCopiedURL = copyQueryIfNeeded(to: originalURL, from: playlistURL)
        guard queryCopiedURL.absoluteString != originalURL.absoluteString else {
            return
        }

        let copiedStatus = await probeSegment(url: queryCopiedURL)
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

    private static func probeSegment(url: URL) async -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "SeSACKey")
        request.setValue(nil, forHTTPHeaderField: "SesacKey")
        request.setValue(nil, forHTTPHeaderField: "Content-Type")
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")

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

    private static func maskedURI(_ uri: String) -> String {
        let descriptor = VideoURLLogDescriptor(rawValue: uri)
        if descriptor.queryExists {
            return "\(descriptor.path)?<redacted>"
        }
        return descriptor.path
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
