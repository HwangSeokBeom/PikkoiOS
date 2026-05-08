import Foundation

enum VideoLiveActivityPlaybackState: String, Sendable {
    case playing
    case paused
    case backgroundPaused
    case ended
}

enum VideoLiveActivityEndReason: String, Sendable {
    case foreground
    case ended
    case replaced
    case manual
}

struct VideoLiveActivitySnapshot: Equatable, Sendable {
    let videoId: String
    let title: String
    let thumbnailURLString: String?
    let playbackState: VideoLiveActivityPlaybackState
    let elapsedTime: Double
    let duration: Double
    let quality: String

    var hasArtwork: Bool {
        thumbnailURLString?.isEmpty == false
    }
}

@MainActor
protocol VideoLiveActivityManaging: AnyObject {
    func startOrUpdate(snapshot: VideoLiveActivitySnapshot?)
    func updatePlaybackState(videoId: String, state: VideoLiveActivityPlaybackState, elapsed: Double)
    func end(videoId: String, reason: VideoLiveActivityEndReason)
}

@MainActor
final class NoopVideoLiveActivityService: VideoLiveActivityManaging {
    static let shared = NoopVideoLiveActivityService()

    func startOrUpdate(snapshot: VideoLiveActivitySnapshot?) {}
    func updatePlaybackState(videoId: String, state: VideoLiveActivityPlaybackState, elapsed: Double) {}
    func end(videoId: String, reason: VideoLiveActivityEndReason) {}
}

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class VideoLiveActivityService: VideoLiveActivityManaging {
    static let shared = VideoLiveActivityService()

    private let logger = Logger(category: "VideoLiveActivity")
    private var latestSnapshotByVideoId: [String: VideoLiveActivitySnapshot] = [:]

    func startOrUpdate(snapshot: VideoLiveActivitySnapshot?) {
        guard isSupported else {
            logger.warning("[VideoLiveActivity] start skipped reason=unsupported")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("[VideoLiveActivity] start skipped reason=disabled")
            return
        }
        guard let snapshot else {
            logger.warning("[VideoLiveActivity] start skipped reason=missingVideo")
            return
        }
        guard !snapshot.videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("[VideoLiveActivity] start skipped reason=missingVideo")
            return
        }
        guard snapshot.playbackState == .playing || snapshot.playbackState == .backgroundPaused else {
            logger.warning("[VideoLiveActivity] start skipped reason=notPlaying")
            return
        }

        logger.debug("[VideoLiveActivity] start requested videoId=\(snapshot.videoId) state=\(snapshot.playbackState.rawValue) elapsed=\(Int(snapshot.elapsedTime)) duration=\(Int(snapshot.duration))")

        if activity(videoId: snapshot.videoId) != nil {
            update(snapshot: snapshot)
            return
        }

        Task { [snapshot] in
            do {
                let activity = try Activity.request(
                    attributes: VideoLiveActivityAttributes(
                        videoId: snapshot.videoId,
                        title: snapshot.title.videoLiveActivityDisplayTitle,
                        thumbnailURLString: snapshot.thumbnailURLString
                    ),
                    content: ActivityContent(
                        state: snapshot.contentState,
                        staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())
                    ),
                    pushType: nil
                )
                await MainActor.run {
                    latestSnapshotByVideoId[snapshot.videoId] = snapshot
                    logger.info("[VideoLiveActivity] started videoId=\(snapshot.videoId) activityId=\(activity.id)")
                }
            } catch {
                await MainActor.run {
                    logger.warning("[VideoLiveActivity] start skipped reason=activityUnavailable")
                }
            }
        }
    }

    func updatePlaybackState(videoId: String, state: VideoLiveActivityPlaybackState, elapsed: Double) {
        guard var snapshot = latestSnapshotByVideoId[videoId] else {
            logger.warning("[VideoLiveActivity] update failed reason=noActiveActivity videoId=\(videoId)")
            return
        }
        snapshot = VideoLiveActivitySnapshot(
            videoId: snapshot.videoId,
            title: snapshot.title,
            thumbnailURLString: snapshot.thumbnailURLString,
            playbackState: state,
            elapsedTime: elapsed,
            duration: snapshot.duration,
            quality: snapshot.quality
        )
        update(snapshot: snapshot)
    }

    func end(videoId: String, reason: VideoLiveActivityEndReason) {
        guard isSupported else { return }
        guard activity(videoId: videoId) != nil else {
            latestSnapshotByVideoId[videoId] = nil
            return
        }
        let finalSnapshot = latestSnapshotByVideoId[videoId].map {
            VideoLiveActivitySnapshot(
                videoId: $0.videoId,
                title: $0.title,
                thumbnailURLString: $0.thumbnailURLString,
                playbackState: .ended,
                elapsedTime: $0.elapsedTime,
                duration: $0.duration,
                quality: $0.quality
            )
        }
        Task { [finalSnapshot, videoId, reason] in
            let didEnd = await Self.endActivityKit(videoId: videoId, finalSnapshot: finalSnapshot)
            await MainActor.run {
                if didEnd {
                    latestSnapshotByVideoId[videoId] = nil
                    logger.info("[VideoLiveActivity] ended videoId=\(videoId) reason=\(reason.rawValue)")
                }
            }
        }
    }

    private var isSupported: Bool {
        if #available(iOS 16.1, *) {
            return true
        }
        return false
    }

    private func update(snapshot: VideoLiveActivitySnapshot) {
        guard activity(videoId: snapshot.videoId) != nil else {
            logger.warning("[VideoLiveActivity] update failed reason=noActiveActivity videoId=\(snapshot.videoId)")
            return
        }
        logger.debug("[VideoLiveActivity] update videoId=\(snapshot.videoId) state=\(snapshot.playbackState.rawValue) elapsed=\(Int(snapshot.elapsedTime))")
        Task { [snapshot] in
            let didUpdate = await Self.updateActivityKit(snapshot: snapshot)
            await MainActor.run {
                if didUpdate {
                    latestSnapshotByVideoId[snapshot.videoId] = snapshot
                } else {
                    logger.warning("[VideoLiveActivity] update failed reason=noActiveActivity videoId=\(snapshot.videoId)")
                }
            }
        }
    }

    private func activity(videoId: String) -> Activity<VideoLiveActivityAttributes>? {
        Activity<VideoLiveActivityAttributes>.activities.first { $0.attributes.videoId == videoId }
    }

    nonisolated private static func updateActivityKit(snapshot: VideoLiveActivitySnapshot) async -> Bool {
        guard let activity = Activity<VideoLiveActivityAttributes>.activities.first(where: { $0.attributes.videoId == snapshot.videoId }) else {
            return false
        }
        await activity.update(
            ActivityContent(
                state: snapshot.contentState,
                staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            )
        )
        return true
    }

    nonisolated private static func endActivityKit(videoId: String, finalSnapshot: VideoLiveActivitySnapshot?) async -> Bool {
        guard let activity = Activity<VideoLiveActivityAttributes>.activities.first(where: { $0.attributes.videoId == videoId }) else {
            return false
        }
        if let finalSnapshot {
            await activity.end(
                ActivityContent(state: finalSnapshot.contentState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        } else {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return true
    }
}

private extension VideoLiveActivitySnapshot {
    var contentState: VideoLiveActivityAttributes.ContentState {
        VideoLiveActivityAttributes.ContentState(
            playbackState: playbackState.rawValue,
            elapsedTime: max(0, elapsedTime),
            duration: max(0, duration),
            quality: quality.userFacingVideoQualityLabel,
            hasArtwork: hasArtwork,
            updatedAt: Date()
        )
    }
}

private extension String {
    var userFacingVideoQualityLabel: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "영상" }
        return trimmed == "auto" ? "자동 화질" : trimmed
    }

    var videoLiveActivityDisplayTitle: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Pikko Video" : trimmed
        guard fallback.count > 44 else { return fallback }
        let endIndex = fallback.index(fallback.startIndex, offsetBy: 44)
        return String(fallback[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
#else
typealias VideoLiveActivityService = NoopVideoLiveActivityService
#endif
