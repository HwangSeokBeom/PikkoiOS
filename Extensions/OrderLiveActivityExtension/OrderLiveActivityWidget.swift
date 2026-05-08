import ActivityKit
import SwiftUI
import WidgetKit

@main
struct OrderLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        OrderLiveActivityWidget()
        VideoLiveActivityWidget()
    }
}

struct OrderLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderLiveActivityAttributes.self) { context in
            OrderLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(context.state.deepLinkURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.storeName)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.statusTitle)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(context.state.progressStep), total: Double(context.state.totalSteps))
                            .tint(.green)
                        Text(context.state.pickupMessage)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Text("\(context.state.progressStep)/\(context.state.totalSteps)")
                    .font(.caption2.bold())
            } compactTrailing: {
                Image(systemName: islandIcon(for: context.state.status))
            } minimal: {
                Image(systemName: islandIcon(for: context.state.status))
            }
            .widgetURL(context.state.deepLinkURL)
        }
    }

    private func islandIcon(for status: String) -> String {
        switch status {
        case "READY_FOR_PICKUP":
            return "bag.fill"
        case "PICKED_UP":
            return "checkmark.circle.fill"
        case "IN_PROGRESS":
            return "flame.fill"
        default:
            return "clock.fill"
        }
    }
}

private struct OrderLiveActivityLockScreenView: View {
    let context: ActivityViewContext<OrderLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.storeName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.attributes.orderCode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(context.state.statusTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }

            ProgressView(value: Double(context.state.progressStep), total: Double(context.state.totalSteps))
                .tint(.green)

            HStack {
                Text(context.state.pickupMessage)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(context.state.updatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }
}

struct VideoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VideoLiveActivityAttributes.self) { context in
            VideoLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(statusTitle(for: context.state.playbackState))
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VideoLiveActivityProgressView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: islandIcon(for: context.state.playbackState))
            } compactTrailing: {
                Text("Pikko")
                    .font(.caption2.bold())
                    .lineLimit(1)
            } minimal: {
                Image(systemName: islandIcon(for: context.state.playbackState))
            }
        }
    }
}

private struct VideoLiveActivityLockScreenView: View {
    let context: ActivityViewContext<VideoLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: context.state.hasArtwork ? "play.rectangle.fill" : "play.rectangle")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusTitle(for: context.state.playbackState))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Pikko Shorts")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }

            VideoLiveActivityProgressView(state: context.state)
        }
        .padding(4)
    }
}

private struct VideoLiveActivityProgressView: View {
    let state: VideoLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress)
                .tint(.green)
            HStack {
                Text(timeText(state.elapsedTime))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeText(state.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progress: Double {
        guard state.duration > 0 else { return 0 }
        return min(max(state.elapsedTime / state.duration, 0), 1)
    }

    private func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private func statusTitle(for playbackState: String) -> String {
    switch playbackState {
    case "playing":
        return "재생 중"
    case "backgroundPaused":
        return "백그라운드 일시정지"
    case "paused":
        return "일시정지"
    case "ended":
        return "종료됨"
    default:
        return "영상"
    }
}

private func islandIcon(for playbackState: String) -> String {
    switch playbackState {
    case "playing":
        return "play.fill"
    case "backgroundPaused", "paused":
        return "pause.fill"
    case "ended":
        return "checkmark.circle.fill"
    default:
        return "play.rectangle.fill"
    }
}
