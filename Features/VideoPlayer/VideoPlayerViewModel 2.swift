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
    private let isPlayerNetworkProbeEnabled: Bool
    private let logger = Logger(category: "VideoPlayer")
    private let qualityLogger = Logger(category: "VideoQuality")

    private var hasLoadedInitialStream = false
    private var streamIssuedAt: Date?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var playerTimeControlObservation: NSKeyValueObservation?
    private var pendingSeekTime: CMTime?
    private var pendingResumeAfterReady = false
    private var activeQuality = "auto"
    private var previousSuccessfulQuality: String?
    private var attemptedPlaybackQualities = Set<String>()
    private var didLogATSConfiguration = false

    init(
        video: Video,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        appConfiguration: AppConfiguration = AppConfiguration(),
        tokenStore: (any TokenStore)? = nil,
        isPlayerNetworkProbeEnabled: Bool = true,
        onVideoUpdated: @escaping (Video) -> Void = { _ in }
    ) {
        self.viewState = VideoPlayerViewState(video: video)
        self.fetchStreamUseCase = fetchStreamUseCase
        self.setLikeUseCase = setLikeUseCase
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
        self.isPlayerNetworkProbeEnabled = isPlayerNetworkProbeEnabled
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
            isPlayerNetworkProbeEnabled: false,
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
        await loadStream(shouldAutoplay: true)
    }

    func retryStream() async {
        await loadStream(shouldAutoplay: true)
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
        let previousQuality = viewState.selectedQuality ?? "auto"
        let nextQuality = quality?.quality ?? "auto"
        guard previousQuality != nextQuality else {
            viewState.isQualityMenuPresented = false
            return
        }

        let url = quality?.url ?? stream.streamURL
        let rawPath = quality?.urlPath ?? stream.streamURLPath
        if source == .actionSheet {
            qualityLogger.debug("[VideoQuality] actionSheet select quality=\(nextQuality)")
        }
        qualityLogger.debug("[VideoQuality] selected quality=\(nextQuality) previous=\(previousQuality)")
        preparePlaybackAttempt(startingWith: nextQuality)

        let currentTime = player?.currentTime() ?? .zero
        let shouldResume = viewState.playbackState == .playing
            || viewState.playbackState == .loadingStream
            || player?.timeControlStatus == .playing
        logger.debug(
            "[VideoPlayer] replace item reason=qualityChanged from=\(previousQuality) to=\(nextQuality) preserveTime=\(currentTime.seconds.isFinite ? currentTime.seconds : 0)"
        )
        setPlaybackState(.loadingStream)

        await replacePlayerItem(
            url: url,
            rawPath: rawPath,
            quality: nextQuality,
            selectedQuality: quality?.quality,
            seekTime: currentTime,
            shouldResume: shouldResume,
            failureMessage: nil
        )
    }

    func handlePlaybackFailure() {
        let message = "재생 URL이 만료되었거나 사용할 수 없습니다."
        if isLikelyExpired() {
            setPlaybackState(.expiredOrUnavailable(message))
        } else {
            setPlaybackState(.failed("영상을 불러오지 못했습니다."))
        }
        logger.error("[VideoPlayer] failed videoId=\(viewState.video.videoId) reason=playbackFailure")
    }

    func handlePlaybackStalled() {
        if isLikelyExpired() {
            setPlaybackState(.expiredOrUnavailable("재생 URL이 만료되었거나 사용할 수 없습니다."))
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

    private func loadStream(shouldAutoplay: Bool) async {
        let videoID = viewState.video.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !videoID.isEmpty else {
            viewState.toastMessage = nil
            viewState.selectedQuality = nil
            setPlaybackState(.failed("영상 정보를 불러올 수 없어요."))
            logger.error("[VideoPlayer] invalid empty videoId")
            return
        }

        setPlaybackState(.loadingStream)
        viewState.toastMessage = nil
        viewState.selectedQuality = nil
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
            preparePlaybackAttempt(startingWith: "auto")
            logger.debug("[VideoPlayer] selected quality=auto urlExists=\(!stream.streamURL.absoluteString.isEmpty)")
            logStreamURL(rawPath: stream.streamURLPath, resolvedURL: stream.streamURL, quality: "auto")
            let playerItem = try await makeAuthorizedPlayerItem(
                url: stream.streamURL,
                quality: "auto",
                rawPath: stream.streamURLPath
            )
            let player = AVPlayer(playerItem: playerItem)
            self.player = player
            installPlayerObserversIfNeeded(for: player)
            installItemStatusObserver(for: playerItem, quality: "auto")
            pendingResumeAfterReady = shouldAutoplay
            pendingSeekTime = nil
        } catch {
            let message = resolveStreamErrorMessage(error)
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

    private func preparePlaybackAttempt(startingWith quality: String) {
        attemptedPlaybackQualities = [quality]
        activeQuality = quality
    }

    private func replacePlayerItem(
        url: URL,
        rawPath: String,
        quality: String,
        selectedQuality: String?,
        seekTime: CMTime,
        shouldResume: Bool,
        failureMessage: String?
    ) async {
        logger.debug("[VideoPlayer] selected quality=\(quality) urlExists=\(!url.absoluteString.isEmpty)")
        logStreamURL(rawPath: rawPath, resolvedURL: url, quality: quality)

        let item: AVPlayerItem
        do {
            item = try await makeAuthorizedPlayerItem(url: url, quality: quality, rawPath: rawPath)
        } catch {
            setPlaybackState(.failed(failureMessage ?? resolveStreamErrorMessage(error)))
            logger.error("[VideoPlayer] player error=\(error.localizedDescription)")
            return
        }

        activeQuality = quality
        viewState.selectedQuality = selectedQuality
        viewState.isQualityMenuPresented = false
        pendingSeekTime = seekTime.seconds.isFinite && seekTime.seconds > 0 ? seekTime : nil
        pendingResumeAfterReady = shouldResume

        if let player {
            installPlayerObserversIfNeeded(for: player)
            installItemStatusObserver(for: item, quality: quality)
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
            if let player {
                installPlayerObserversIfNeeded(for: player)
            }
            installItemStatusObserver(for: item, quality: quality)
        }
    }

    private func handleItemFailure(_ item: AVPlayerItem, quality: String) async {
        let itemError = item.error
        let nsError = itemError as NSError?
        logger.error(
            "[VideoPlayer] item status=failed quality=\(quality) error=\(itemError?.localizedDescription ?? "unknown") domain=\(nsError?.domain ?? "nil") code=\(nsError?.code ?? 0)"
        )
        logItemErrorLog(for: item)
        logAccessLog(for: item)
        if let playerError = player?.error {
            logger.error("[VideoPlayer] player error=\(playerError.localizedDescription)")
        }

        guard let fallback = fallbackQuality(afterFailureOf: quality) else {
            setPlaybackState(.failed("영상을 재생하지 못했습니다."))
            return
        }

        qualityLogger.debug("[VideoQuality] fallback from=\(quality) to=\(fallback.identifier) reason=playerItemFailed")
        attemptedPlaybackQualities.insert(fallback.identifier)
        setPlaybackState(.loadingStream)
        await replacePlayerItem(
            url: fallback.url,
            rawPath: fallback.rawPath,
            quality: fallback.identifier,
            selectedQuality: fallback.selectedQuality,
            seekTime: player?.currentTime() ?? pendingSeekTime ?? .zero,
            shouldResume: pendingResumeAfterReady || player?.timeControlStatus == .playing,
            failureMessage: "영상을 재생하지 못했습니다."
        )
    }

    private func fallbackQuality(afterFailureOf failedQuality: String) -> ResolvedVideoQuality? {
        guard let stream = viewState.stream else { return nil }
        var candidateIDs: [String] = []

        if failedQuality != "auto" {
            candidateIDs.append("auto")
        }

        if let previousSuccessfulQuality,
           previousSuccessfulQuality != failedQuality {
            candidateIDs.append(previousSuccessfulQuality)
        }

        candidateIDs.append(contentsOf: availableQualityTitles())

        for candidateID in candidateIDs where candidateID != failedQuality && !attemptedPlaybackQualities.contains(candidateID) {
            if candidateID == "auto" {
                return ResolvedVideoQuality(
                    identifier: "auto",
                    selectedQuality: nil,
                    url: stream.streamURL,
                    rawPath: stream.streamURLPath
                )
            }

            if let quality = stream.qualities.first(where: { $0.quality == candidateID }) {
                return ResolvedVideoQuality(
                    identifier: quality.quality,
                    selectedQuality: quality.quality,
                    url: quality.url,
                    rawPath: quality.urlPath
                )
            }
        }

        return nil
    }

    private func logStreamURL(rawPath: String, resolvedURL: URL, quality: String) {
        let rawDescriptor = VideoURLLogDescriptor(rawValue: rawPath)
        logger.debug(
            "[VideoPlayer] stream raw quality=\(quality) path=\(rawDescriptor.path) ext=\(rawDescriptor.ext) queryExists=\(rawDescriptor.queryExists)"
        )

        let resolvedDescriptor = VideoURLLogDescriptor(url: resolvedURL)
        logger.debug(
            "[VideoPlayer] stream resolved quality=\(quality) scheme=\(resolvedDescriptor.scheme) host=\(resolvedDescriptor.host) port=\(resolvedDescriptor.port) path=\(resolvedDescriptor.path) ext=\(resolvedDescriptor.ext) queryExists=\(resolvedDescriptor.queryExists)"
        )
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
    }

    private func makeAuthorizedPlayerItem(url: URL, quality: String, rawPath: String) async throws -> AVPlayerItem {
        _ = rawPath
        logger.debug(
            "[VideoPlayer] build asset quality=\(quality) url=\(VideoURLLogDescriptor(url: url).redactedAbsoluteString) authExists=false sesacKeyExists=false assetHeaders=false"
        )
        logATSConfigurationIfNeeded(for: url)
        let asset = AVURLAsset(url: url)
        return AVPlayerItem(asset: asset)
    }

    private func installPlayerObserversIfNeeded(for player: AVPlayer) {
        playerStatusObservation?.invalidate()
        playerTimeControlObservation?.invalidate()

        playerStatusObservation = player.observe(\.status, options: [.new]) { [weak self] observedPlayer, _ in
            Task { @MainActor in
                guard let self else { return }
                if observedPlayer.status == .failed {
                    self.logger.error("[VideoPlayer] player error=\(observedPlayer.error?.localizedDescription ?? "unknown")")
                    self.setPlaybackState(.failed("영상을 재생하지 못했습니다."))
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

    private func installItemStatusObserver(for item: AVPlayerItem, quality: String) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] observedItem, _ in
            Task { @MainActor in
                guard let self, item === observedItem else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.logger.debug(
                        "[VideoPlayer] item status=readyToPlay quality=\(quality)"
                    )
                    self.previousSuccessfulQuality = quality
                    self.activeQuality = quality
                    self.logAccessLog(for: observedItem)
                    let seekTime = self.pendingSeekTime
                    let shouldResume = self.pendingResumeAfterReady
                    self.pendingSeekTime = nil
                    self.pendingResumeAfterReady = false
                    self.setPlaybackState(.ready)

                    if let seekTime {
                        observedItem.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                            Task { @MainActor in
                                guard let self else { return }
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
                    await self.handleItemFailure(observedItem, quality: quality)
                case .unknown:
                    self.logger.debug(
                        "[VideoPlayer] item status=unknown videoID=\(self.viewState.video.videoId) quality=\(quality)"
                    )
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func logItemErrorLog(for item: AVPlayerItem) {
        guard let events = item.errorLog()?.events,
              !events.isEmpty else {
            logger.error("[VideoPlayer] item errorLog empty=true")
            return
        }

        for event in events {
            let uriPath = event.uri.map { VideoURLLogDescriptor(rawValue: $0).path } ?? "nil"
            logger.error(
                "[VideoPlayer] errorLog event uri=\(uriPath) statusCode=\(event.errorStatusCode) serverAddress=\(event.serverAddress ?? "nil") playbackSessionID=\(event.playbackSessionID ?? "nil") errorDomain=\(event.errorDomain) errorComment=\(event.errorComment ?? "nil")"
            )
        }
    }

    private func logAccessLog(for item: AVPlayerItem) {
        guard let event = item.accessLog()?.events.last else {
            logger.debug("[VideoPlayer] accessLog empty=true")
            return
        }

        logger.debug(
            "[VideoPlayer] accessLog indicatedBitrate=\(event.indicatedBitrate) observedBitrate=\(event.observedBitrate) numberOfStalls=\(event.numberOfStalls)"
        )
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

    private func resolveErrorMessage(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}

private struct ResolvedVideoQuality {
    let identifier: String
    let selectedQuality: String?
    let url: URL
    let rawPath: String
}

private struct VideoURLLogDescriptor {
    let scheme: String
    let host: String
    let port: String
    let path: String
    let ext: String
    let queryExists: Bool

    init(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        self.scheme = url.scheme ?? "nil"
        self.host = url.host ?? "nil"
        self.port = url.port.map(String.init) ?? "nil"
        self.path = components?.percentEncodedPath.removingPercentEncoding ?? url.path
        self.ext = url.pathExtension.isEmpty ? "nil" : url.pathExtension
        self.queryExists = components?.percentEncodedQuery?.isEmpty == false
    }

    init(rawValue: String) {
        if let components = URLComponents(string: rawValue) {
            self.scheme = components.scheme ?? "nil"
            self.host = components.host ?? "nil"
            self.port = components.port.map(String.init) ?? "nil"
            self.path = components.percentEncodedPath.removingPercentEncoding
                ?? (components.path.isEmpty ? rawValue.components(separatedBy: "?").first ?? rawValue : components.path)
            self.ext = URL(fileURLWithPath: components.path).pathExtension.isEmpty
                ? "nil"
                : URL(fileURLWithPath: components.path).pathExtension
            self.queryExists = components.percentEncodedQuery?.isEmpty == false
        } else {
            let path = rawValue.components(separatedBy: "?").first ?? rawValue
            self.scheme = "nil"
            self.host = "nil"
            self.port = "nil"
            self.path = path
            self.ext = (path as NSString).pathExtension.isEmpty ? "nil" : (path as NSString).pathExtension
            self.queryExists = rawValue.contains("?")
        }
    }

    var redactedAbsoluteString: String {
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
}
