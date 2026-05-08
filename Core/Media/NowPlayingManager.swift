import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private let logger = Logger(category: "NowPlaying")
    private let uxLogger = Logger(category: "NowPlayingUX")
    private var commandTargets: [RemoteCommandTarget] = []
    private weak var player: AVPlayer?
    private var configuredSession = false
    private var activeVideoID: String?
    private var lastMetadataKey: MetadataKey?
    private var artworkCache: [String: UIImage] = [:]
    private var lastPlaybackUpdate: PlaybackUpdate?

    private init() {
        logger.debug("[NowPlaying] owner=videoOnly orderIntegration=false")
    }

    func configureSessionIfNeeded(player: AVPlayer, videoId: String? = nil, context: VideoPlaybackContext = .detail) {
        self.player = player
        guard !configuredSession else {
            registerRemoteCommandsIfNeeded()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            configuredSession = true
            logger.debug("[AudioSession] category=playback active=true reason=videoPlayback")
            registerRemoteCommandsIfNeeded()
        } catch {
            logger.warning("[NowPlaying] skipped reason=sessionConfigurationFailed")
        }
    }

    func updateMetadata(
        video: Video,
        subtitle: String? = nil,
        albumTitle: String = "Pikko Shorts",
        artworkData: Data? = nil
    ) {
        logger.debug("[NowPlaying] activate requested videoId=\(video.videoId)")
        activeVideoID = video.videoId
        let displayTitle = Self.displayTitleForNowPlaying(video.title)
        let displaySubtitle = Self.displaySubtitleForNowPlaying(subtitle)
        let duration = normalizedDuration(video.duration)
        let artworkResult = artwork(for: video, artworkData: artworkData)
        let metadataKey = MetadataKey(
            videoID: video.videoId,
            title: displayTitle,
            subtitle: displaySubtitle,
            albumTitle: albumTitle,
            duration: duration,
            hasRealArtwork: artworkResult.isRealArtwork
        )

        uxLogger.debug("[NowPlayingUX] displayTitle originalLength=\(video.title.count) displayLength=\(displayTitle.count)")
        uxLogger.debug("[NowPlayingUX] subtitle source=\(subtitle?.isEmpty == false ? "provided" : "fallback") value=\(displaySubtitle)")
        uxLogger.debug("[NowPlayingUX] qualityLabel omitted reason=internalValue")

        if lastMetadataKey == metadataKey {
            logger.debug("[NowPlaying] activate skipped reason=sameMetadata videoId=\(video.videoId)")
            return
        }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = displayTitle
        info[MPMediaItemPropertyArtist] = displaySubtitle
        info[MPMediaItemPropertyAlbumTitle] = albumTitle
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        } else {
            info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
            logger.debug("[NowPlaying] update skipped reason=invalidDuration videoId=\(video.videoId)")
        }
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        if let image = artworkResult.image {
            if image.size.width.isFinite, image.size.height.isFinite, image.size.width > 0, image.size.height > 0 {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            } else {
                info.removeValue(forKey: MPMediaItemPropertyArtwork)
                logger.debug("[NowPlaying] artwork fallback omitted reason=invalidImageSize videoId=\(video.videoId)")
            }
        } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastMetadataKey = metadataKey
        logger.debug("[NowPlaying] activate videoId=\(video.videoId) title=\(displayTitle) subtitle=\(displaySubtitle)")
    }

    func updatePlaybackState(player: AVPlayer?, duration: Double?, elapsed: Double, rate: Float? = nil, force: Bool = false) {
        guard let player else {
            logger.debug("[NowPlaying] skipped reason=noCurrentItem")
            return
        }
        self.player = player
        let playbackRate = rate ?? player.rate
        let videoId = activeVideoID ?? "nil"
        let normalizedElapsed = elapsed.isFinite && !elapsed.isNaN ? max(0, elapsed) : 0
        let normalizedDuration = normalizedDuration(duration)
        let nextUpdate = PlaybackUpdate(
            elapsedBucket: Int(normalizedElapsed),
            durationBucket: Int(normalizedDuration ?? 0),
            rate: playbackRate
        )

        if !force,
           let lastPlaybackUpdate,
           lastPlaybackUpdate.shouldThrottle(next: nextUpdate) {
            logger.debug("[NowPlaying] update skipped reason=throttled videoId=\(videoId)")
            return
        }

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if let normalizedDuration {
            info[MPMediaItemPropertyPlaybackDuration] = normalizedDuration
        } else {
            info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
            logger.debug("[NowPlaying] update skipped reason=invalidDuration videoId=\(videoId)")
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = normalizedElapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastPlaybackUpdate = nextUpdate
        logger.debug("[NowPlaying] update elapsed=\(Int(normalizedElapsed)) duration=\(Int(normalizedDuration ?? 0)) rate=\(playbackRate)")
    }

    func clear(reason: String) {
        guard player != nil || configuredSession || MPNowPlayingInfoCenter.default().nowPlayingInfo != nil else {
            logger.debug("[NowPlaying] clear skipped reason=alreadyClear")
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        player = nil
        activeVideoID = nil
        lastMetadataKey = nil
        lastPlaybackUpdate = nil
        if configuredSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            configuredSession = false
        }
        logger.debug("[NowPlaying] clear reason=\(reason)")
    }

    private func registerRemoteCommandsIfNeeded() {
        logger.debug("[RemoteCommand] register requested owner=playbackCoordinator")
        guard commandTargets.isEmpty else {
            logger.debug("[RemoteCommand] skipped reason=alreadyRegistered")
            return
        }

        let commandCenter = MPRemoteCommandCenter.shared()
        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                let activeVideoId = VideoPlaybackCoordinator.shared.currentVideoId
                self?.logger.debug("[RemoteCommand] command=play received activeVideoId=\(activeVideoId ?? "nil")")
                if !VideoPlaybackCoordinator.shared.play() {
                    self?.logger.debug("[RemoteCommand] command ignored reason=noActivePlayer")
                }
            }
            return .success
        }
        commandTargets.append(RemoteCommandTarget(command: commandCenter.playCommand, target: playTarget))

        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                let activeVideoId = VideoPlaybackCoordinator.shared.currentVideoId
                self?.logger.debug("[RemoteCommand] command=pause received activeVideoId=\(activeVideoId ?? "nil")")
                if !VideoPlaybackCoordinator.shared.pause() {
                    self?.logger.debug("[RemoteCommand] command ignored reason=noActivePlayer")
                }
            }
            return .success
        }
        commandTargets.append(RemoteCommandTarget(command: commandCenter.pauseCommand, target: pauseTarget))

        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                let activeVideoId = VideoPlaybackCoordinator.shared.currentVideoId
                self?.logger.debug("[RemoteCommand] command=toggle received activeVideoId=\(activeVideoId ?? "nil")")
                if !VideoPlaybackCoordinator.shared.togglePlayPause() {
                    self?.logger.debug("[RemoteCommand] command ignored reason=noActivePlayer")
                }
            }
            return .success
        }
        commandTargets.append(RemoteCommandTarget(command: commandCenter.togglePlayPauseCommand, target: toggleTarget))

        let seekTarget = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                let activeVideoId = VideoPlaybackCoordinator.shared.currentVideoId
                self?.logger.debug("[RemoteCommand] command=seek received activeVideoId=\(activeVideoId ?? "nil") position=\(Int(positionEvent.positionTime))")
                if !VideoPlaybackCoordinator.shared.seek(to: positionEvent.positionTime) {
                    self?.logger.debug("[RemoteCommand] command ignored reason=noActivePlayer")
                }
            }
            return .success
        }
        commandTargets.append(RemoteCommandTarget(command: commandCenter.changePlaybackPositionCommand, target: seekTarget))
        logger.debug("[RemoteCommand] registered commands=play,pause,toggle,seek")
    }

    private func unregisterRemoteCommands() {
        guard !commandTargets.isEmpty else {
            logger.debug("[RemoteCommand] remove skipped reason=alreadyRemoved")
            return
        }
        let snapshot = commandTargets
        commandTargets.removeAll()
        for registration in snapshot {
            registration.command.removeTarget(registration.target)
        }
        logger.debug("[RemoteCommand] removed reason=noActivePlayback")
    }

    private struct RemoteCommandTarget {
        let command: MPRemoteCommand
        let target: Any
    }

    private struct MetadataKey: Equatable {
        let videoID: String
        let title: String
        let subtitle: String
        let albumTitle: String
        let duration: Double?
        let hasRealArtwork: Bool
    }

    private struct PlaybackUpdate {
        let elapsedBucket: Int
        let durationBucket: Int
        let rate: Float

        func shouldThrottle(next: PlaybackUpdate) -> Bool {
            elapsedBucket == next.elapsedBucket
                && durationBucket == next.durationBucket
                && abs(rate - next.rate) < 0.01
        }
    }

    private struct ArtworkResult {
        let image: UIImage?
        let isRealArtwork: Bool
    }

    private func artwork(for video: Video, artworkData: Data?) -> ArtworkResult {
        if let cachedArtwork = artworkCache[video.videoId] {
            return ArtworkResult(image: cachedArtwork, isRealArtwork: true)
        }

        if let artworkData,
           let image = UIImage(data: artworkData)?.downsampled(maxPixel: 600) {
            artworkCache[video.videoId] = image
            uxLogger.debug("[NowPlayingUX] artwork downsampled size=\(Int(image.size.width))x\(Int(image.size.height))")
            logger.debug("[NowPlaying] artwork loaded videoId=\(video.videoId) size=\(Int(image.size.width))x\(Int(image.size.height))")
            return ArtworkResult(image: image, isRealArtwork: true)
        }

        logger.debug("[NowPlaying] artwork fallback reason=loadFailed videoId=\(video.videoId)")
        logger.debug("[NowPlaying] artwork omitted reason=loadFailed videoId=\(video.videoId)")
        return ArtworkResult(image: fallbackArtwork(videoId: video.videoId), isRealArtwork: false)
    }

    private func fallbackArtwork(videoId: String) -> UIImage? {
        if let icon = UIImage(named: "AppIcon") {
            return icon.downsampled(maxPixel: 600) ?? icon
        }
        logger.debug("[NowPlaying] artwork fallback omitted reason=missingFallbackImage videoId=\(videoId)")
        return nil
    }

    private func normalizedDuration(_ duration: Double?) -> Double? {
        guard let duration, duration.isFinite, !duration.isNaN, duration > 0 else { return nil }
        return duration
    }

    private static func displaySubtitleForNowPlaying(_ subtitle: String?) -> String {
        let trimmed = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Pikko Shorts" : trimmed
    }

    private static func displayTitleForNowPlaying(_ title: String) -> String {
        let trimmed = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .condensingRepeatedLeadingEmoji()
        let fallback = trimmed.isEmpty ? "Pikko Video" : trimmed
        return fallback.safePrefixWithEllipsis(maxLength: 44)
    }
}

private extension UIImage {
    func downsampled(maxPixel: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        guard longest > maxPixel else { return self }
        let scale = maxPixel / longest
        let targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension String {
    func safePrefixWithEllipsis(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let endIndex = index(startIndex, offsetBy: maxLength)
        return String(self[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func condensingRepeatedLeadingEmoji() -> String {
        var result = ""
        var hasPreservedLeadingEmoji = false
        var isStillInPrefix = true

        for character in self {
            if isStillInPrefix, character.isEmojiLike {
                if !hasPreservedLeadingEmoji {
                    result.append(character)
                    hasPreservedLeadingEmoji = true
                }
                continue
            }

            if character.isWhitespace, result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            isStillInPrefix = false
            result.append(character)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    var isEmojiLike: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
        }
    }
}

@MainActor
final class VideoPlaybackCoordinator {
    static let shared = VideoPlaybackCoordinator()

    private let logger = Logger(category: "VideoPlayback")
    private let sessionLogger = Logger(category: "PlaybackSession")
    private weak var activePlayer: AVPlayer?
    private weak var activeItem: AVPlayerItem?
    private var activeVideoID: String?
    private var activeContext: VideoPlaybackContext?
    private var activeGeneration: Int?
    private var activeSessionID: String?
    private var activeStream: VideoStream?
    private var periodicTimeObserverRegistration: PeriodicTimeObserverRegistration?
    private var tickHandler: ((VideoPlaybackTick) -> Void)?

    var currentVideoId: String? {
        activeVideoID
    }

    var currentSessionId: String? {
        activeSessionID
    }

    var currentContext: VideoPlaybackContext? {
        activeContext
    }

    func activate(player: AVPlayer, videoId: String, context: VideoPlaybackContext) {
        activate(player: player, videoId: videoId, context: context, item: player.currentItem, generation: nil, onTick: nil)
    }

    func activate(
        player: AVPlayer,
        videoId: String,
        context: VideoPlaybackContext,
        item: AVPlayerItem?,
        generation: Int?,
        stream: VideoStream? = nil,
        onTick: ((VideoPlaybackTick) -> Void)?
    ) {
        logger.debug("[PlaybackOwner] mutation on MainActor=\(Thread.isMainThread) source=activate")
        if let activeContext, activeContext != context {
            logger.debug("[PlaybackOwner] activeContext changed from=\(activeContext.rawValue) to=\(context.rawValue) videoId=\(videoId)")
        }
        if let activePlayer, activePlayer !== player {
            removePeriodicTimeObserver(videoId: activeVideoID)
        } else if activePlayer === player, activeVideoID == videoId, periodicTimeObserverRegistration != nil {
            logger.debug("[PlaybackOwner] duplicate player creation blocked videoId=\(videoId)")
        }
        if activeSessionID == nil || activeVideoID != videoId || activePlayer !== player {
            activeSessionID = UUID().uuidString
            sessionLogger.debug("[PlaybackSession] created sessionId=\(activeSessionID ?? "nil") videoId=\(videoId) context=\(context.rawValue)")
        }
        activePlayer = player
        activeItem = item
        activeVideoID = videoId
        activeContext = context
        activeGeneration = generation
        if let stream {
            activeStream = stream
        }
        tickHandler = onTick
        logger.debug("[VideoPlayback] coordinator active videoId=\(videoId) context=\(context.rawValue)")
        logger.debug("[PlaybackOwner] currentItem replaced videoId=\(videoId) generation=\(generation.map(String.init) ?? "nil")")
        installPeriodicTimeObserverIfNeeded(for: player, item: item, videoId: videoId, context: context, generation: generation)
    }

    func deactivate(videoId: String, context: VideoPlaybackContext) {
        guard activeVideoID == videoId else { return }
        guard activeContext == context else {
            if activeContext == .detail, context == .shorts {
                sessionLogger.debug("[PlaybackSession] stale cleanup ignored source=shortsDetach reason=ownershipMovedToDetail videoId=\(videoId)")
                logger.debug("[PlaybackOwner] coordinator inactive skipped reason=activeContextIsDetail videoId=\(videoId)")
            }
            return
        }
        removePeriodicTimeObserver(videoId: videoId)
        activePlayer = nil
        activeItem = nil
        activeVideoID = nil
        activeContext = nil
        activeGeneration = nil
        activeSessionID = nil
        activeStream = nil
        tickHandler = nil
        logger.debug("[VideoPlayback] coordinator inactive videoId=\(videoId)")
    }

    @discardableResult
    func transferToDetail(videoId: String) -> Bool {
        guard activeVideoID == videoId,
              activeContext == .shorts,
              activePlayer != nil,
              activeItem != nil else {
            logger.debug("[VideoPlayback] transfer skipped reason=noMatchingShortsSession videoId=\(videoId)")
            return false
        }

        let sessionID = activeSessionID ?? UUID().uuidString
        activeSessionID = sessionID
        logger.debug("[VideoPlayback] transfer started from=shorts to=detail videoId=\(videoId)")
        logger.debug("[PlaybackOwner] activeContext changed from=shorts to=detail videoId=\(videoId)")
        logger.debug("[PlaybackOwner] currentItem reused reason=sameVideoOriginalTransition videoId=\(videoId)")
        logger.debug("[PlayerTimeObserver] transfer owner from=shorts to=detail videoId=\(videoId)")
        logger.debug("[PlayerTimeObserver] add skipped reason=alreadyExists videoId=\(videoId)")
        Logger(category: "NowPlaying").debug("[NowPlaying] preserve reason=sameVideoOriginalTransition videoId=\(videoId)")
        Logger(category: "PiP").debug("[PiP] ownership transfer from=shorts to=detail videoId=\(videoId)")
        activeContext = .detail
        sessionLogger.debug("[PlaybackSession] transferred sessionId=\(sessionID) from=shorts to=detail videoId=\(videoId)")
        logger.debug("[VideoPlayback] transfer completed from=shorts to=detail videoId=\(videoId) playerReused=true itemReused=true")
        return true
    }

    func currentPlaybackSession(videoId: String, context: VideoPlaybackContext) -> ActiveVideoPlaybackSession? {
        guard activeVideoID == videoId,
              activeContext == context,
              let activePlayer,
              let activeItem else {
            return nil
        }
        return ActiveVideoPlaybackSession(
            sessionId: activeSessionID,
            videoId: videoId,
            context: context,
            player: activePlayer,
            item: activeItem,
            itemGeneration: activeGeneration,
            stream: activeStream
        )
    }

    func isCurrentSession(_ sessionId: String?, videoId: String, context: VideoPlaybackContext? = nil, generation: Int? = nil) -> Bool {
        guard activeVideoID == videoId else { return false }
        if let context, activeContext != context { return false }
        if let sessionId, activeSessionID != sessionId { return false }
        if let generation, activeGeneration != generation { return false }
        return true
    }

#if DEBUG
    func resetForTesting() {
        removePeriodicTimeObserver(videoId: activeVideoID)
        activePlayer = nil
        activeItem = nil
        activeVideoID = nil
        activeContext = nil
        activeGeneration = nil
        activeSessionID = nil
        activeStream = nil
        tickHandler = nil
    }
#endif

    @discardableResult
    func play() -> Bool {
        guard let activePlayer else { return false }
        activePlayer.play()
        return true
    }

    @discardableResult
    func pause() -> Bool {
        guard let activePlayer else { return false }
        activePlayer.pause()
        return true
    }

    @discardableResult
    func togglePlayPause() -> Bool {
        guard let activePlayer else { return false }
        activePlayer.rate == 0 ? activePlayer.play() : activePlayer.pause()
        return true
    }

    @discardableResult
    func seek(to seconds: Double) -> Bool {
        guard let activePlayer, seconds.isFinite, !seconds.isNaN else { return false }
        activePlayer.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        return true
    }

    func removeTimeObserver(videoId: String?) {
        if let videoId,
           activeVideoID == videoId,
           activeContext == .detail {
            logger.debug("[PlayerTimeObserver] remove skipped reason=sessionMismatch videoId=\(videoId)")
            return
        }
        removePeriodicTimeObserver(videoId: videoId)
    }

    private func installPeriodicTimeObserverIfNeeded(
        for player: AVPlayer,
        item: AVPlayerItem?,
        videoId: String,
        context: VideoPlaybackContext,
        generation: Int?
    ) {
        logger.debug("[PlayerTimeObserver] add requested videoId=\(videoId) existingToken=\(periodicTimeObserverRegistration != nil)")
        guard item != nil else {
            logger.debug("[PlayerTimeObserver] add skipped reason=noCurrentItem videoId=\(videoId)")
            return
        }
        if let registration = periodicTimeObserverRegistration {
            if registration.matches(player: player) {
                logger.debug("[PlayerTimeObserver] add skipped reason=alreadyExists videoId=\(videoId)")
                return
            }
            removePeriodicTimeObserver(videoId: activeVideoID)
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player, weak item] time in
            Task { @MainActor in
                self?.handlePeriodicTimeObserverTick(
                    time,
                    player: player,
                    item: item,
                    videoId: videoId,
                    installedContext: context,
                    installedGeneration: generation
                )
            }
        }
        periodicTimeObserverRegistration = PeriodicTimeObserverRegistration(player: player, token: token)
        logger.debug("[PlayerTimeObserver] added videoId=\(videoId) queue=main")
    }

    private func handlePeriodicTimeObserverTick(
        _ time: CMTime,
        player: AVPlayer?,
        item: AVPlayerItem?,
        videoId: String,
        installedContext: VideoPlaybackContext,
        installedGeneration: Int?
    ) {
        guard activeVideoID == videoId,
              let activePlayer,
              let player,
              activePlayer === player,
              activeItem === item,
              player.currentItem === item else {
            logger.debug("[PlayerTimeObserver] tick skipped reason=inactiveSession videoId=\(videoId)")
            if let installedGeneration, activeGeneration != installedGeneration {
                logger.debug("[PlaybackOwner] stale item callback ignored generation=\(installedGeneration)")
            }
            if activeContext != installedContext {
                sessionLogger.debug("[PlaybackSession] stale callback ignored source=timeObserver videoId=\(videoId) sessionId=\(activeSessionID ?? "nil")")
            }
            return
        }

        guard VideoPlaybackTiming.safeSeconds(time) != nil else {
            logger.debug("[PlayerTimeObserver] tick skipped reason=invalidTime videoId=\(videoId)")
            return
        }

        tickHandler?(
            VideoPlaybackTick(
                videoId: videoId,
                context: activeContext ?? installedContext,
                generation: activeGeneration,
                sessionId: activeSessionID,
                player: player,
                item: item,
                time: time
            )
        )
    }

    private func removePeriodicTimeObserver(videoId: String?) {
        guard let registration = periodicTimeObserverRegistration else {
            logger.debug("[PlayerTimeObserver] remove skipped reason=alreadyRemoved")
            return
        }
        if !registration.invalidate() {
            logger.debug("[PlayerTimeObserver] remove skipped reason=alreadyRemoved")
        }
        periodicTimeObserverRegistration = nil
        logger.debug("[PlayerTimeObserver] removed videoId=\(videoId ?? "nil")")
    }
}

struct ActiveVideoPlaybackSession {
    let sessionId: String?
    let videoId: String
    let context: VideoPlaybackContext
    let player: AVPlayer
    let item: AVPlayerItem
    let itemGeneration: Int?
    let stream: VideoStream?
}

struct VideoPlaybackTick {
    let videoId: String
    let context: VideoPlaybackContext
    let generation: Int?
    let sessionId: String?
    let player: AVPlayer
    let item: AVPlayerItem?
    let time: CMTime
}

enum VideoPlaybackTiming {
    static func safeSeconds(_ time: CMTime) -> Double? {
        guard time.isValid,
              !time.isIndefinite,
              time.seconds.isFinite,
              !time.seconds.isNaN else {
            return nil
        }
        return max(0, time.seconds)
    }
}

private final class PeriodicTimeObserverRegistration: @unchecked Sendable {
    private weak var player: AVPlayer?
    private let token: Any
    private var isInvalidated = false

    init(player: AVPlayer, token: Any) {
        self.player = player
        self.token = token
    }

    func matches(player: AVPlayer) -> Bool {
        self.player === player && !isInvalidated
    }

    func invalidate() -> Bool {
        guard !isInvalidated else { return false }
        isInvalidated = true
        player?.removeTimeObserver(token)
        return true
    }
}
