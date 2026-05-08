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
                .activityBackgroundTint(Color(.systemBackground).opacity(0.92))
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(context.state.deepLinkURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    OrderDynamicIslandExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    OrderDynamicIslandExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    OrderDynamicIslandExpandedBottomView(context: context)
                }
            } compactLeading: {
                OrderStatusIcon(status: context.state.status, size: 15)
            } compactTrailing: {
                let statusDisplay = OrderLiveActivityStatusDisplay.map(status: context.state.status)
                let _ = OrderLiveActivityDebugLog.layout(
                    family: "dynamicIslandCompact",
                    orderCode: context.attributes.orderCode,
                    status: context.state.status,
                    title: context.attributes.storeName,
                    orderCodeDisplay: OrderLiveActivityTextPolicy.displayOrderCode(context.attributes.orderCode, mode: .short),
                    compactStatus: statusDisplay.compact
                )
                Text(statusDisplay.compact)
                    .font(.caption2.bold())
                    .foregroundStyle(statusTint(for: context.state.status))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
            } minimal: {
                OrderStatusIcon(status: context.state.status, size: 14)
            }
            .widgetURL(context.state.deepLinkURL)
        }
    }
}

private func orderIslandIcon(for status: String) -> String {
    switch normalizedOrderStatus(status) {
    case "READY_FOR_PICKUP":
        return "bag.fill"
    case "PICKED_UP":
        return "checkmark.circle.fill"
    case "IN_PROGRESS":
        return "flame.fill"
    case "APPROVED":
        return "checkmark.seal.fill"
    case "CANCELLED", "CANCELED", "REJECTED", "DENIED", "FAILED":
        return "xmark.circle.fill"
    default:
        return "clock.fill"
    }
}

private struct OrderDynamicIslandExpandedLeadingView: View {
    let context: ActivityViewContext<OrderLiveActivityAttributes>

    var body: some View {
        let statusDisplay = OrderLiveActivityStatusDisplay.map(status: context.state.status)
        HStack(spacing: 6) {
            OrderStatusIcon(status: context.state.status, size: 16)
            Text(statusDisplay.badge)
                .font(.caption.bold())
                .foregroundStyle(statusTint(for: context.state.status))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct OrderDynamicIslandExpandedTrailingView: View {
    let context: ActivityViewContext<OrderLiveActivityAttributes>

    var body: some View {
        let orderCode = OrderLiveActivityTextPolicy.displayOrderCode(context.attributes.orderCode, mode: .short)
        Text(orderCode.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .truncationMode(.middle)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct OrderDynamicIslandExpandedBottomView: View {
    let context: ActivityViewContext<OrderLiveActivityAttributes>

    var body: some View {
        let statusDisplay = OrderLiveActivityStatusDisplay.map(status: context.state.status)
        let title = OrderLiveActivityTextPolicy.displayTitle(context.attributes.storeName, maxLength: 22)
        let orderCode = OrderLiveActivityTextPolicy.displayOrderCode(context.attributes.orderCode, mode: .medium)
        let _ = OrderLiveActivityDebugLog.layout(
            family: "dynamicIslandExpanded",
            orderCode: context.attributes.orderCode,
            status: context.state.status,
            title: context.attributes.storeName,
            orderCodeDisplay: orderCode,
            compactStatus: statusDisplay.compact
        )

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .truncationMode(.tail)
                .layoutPriority(1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(statusDisplay.message)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(context.state.updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                }

                Text(statusDisplay.message)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            OrderProgressBar(
                progress: statusDisplay.progress,
                status: context.state.status
            )
        }
    }
}

private struct OrderLiveActivityLockScreenView: View {
    let context: ActivityViewContext<OrderLiveActivityAttributes>

    var body: some View {
        let statusDisplay = OrderLiveActivityStatusDisplay.map(status: context.state.status)
        let title = OrderLiveActivityTextPolicy.displayTitle(context.attributes.storeName, maxLength: 22)
        let orderCode = OrderLiveActivityTextPolicy.displayOrderCode(context.attributes.orderCode, mode: .medium)
        let _ = OrderLiveActivityDebugLog.layout(
            family: "lockScreen",
            orderCode: context.attributes.orderCode,
            status: context.state.status,
            title: context.attributes.storeName,
            orderCodeDisplay: orderCode,
            compactStatus: statusDisplay.compact
        )

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                OrderStatusIcon(status: context.state.status, size: 16)
                    .frame(width: 34, height: 34)
                    .background(statusTint(for: context.state.status).opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Text(orderCode.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                OrderStatusBadge(title: statusDisplay.badge, status: context.state.status)
                    .layoutPriority(2)
            }

            OrderProgressBar(
                progress: statusDisplay.progress,
                status: context.state.status
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(statusDisplay.message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(context.state.updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusDisplay.message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .truncationMode(.tail)
                    Text(context.state.updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct OrderStatusIcon: View {
    let status: String
    let size: CGFloat

    var body: some View {
        Image(systemName: orderIslandIcon(for: status))
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(statusTint(for: status))
            .accessibilityHidden(true)
    }
}

private struct OrderStatusBadge: View {
    let title: String
    let status: String

    var body: some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(statusTint(for: status))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(statusTint(for: status).opacity(0.16))
            .clipShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
    }
}

private struct OrderProgressBar: View {
    let progress: Double
    let status: String

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(progressTrackTint(for: status))
                if clampedProgress > 0 {
                    Capsule()
                        .fill(progressFillTint(for: status))
                        .frame(width: max(5, proxy.size.width * clampedProgress))
                }
            }
        }
        .frame(height: 5)
        .accessibilityLabel("주문 진행률")
        .accessibilityValue("\(Int(clampedProgress * 100))퍼센트")
    }
}

private func statusTint(for status: String) -> Color {
    switch normalizedOrderStatus(status) {
    case "READY_FOR_PICKUP":
        return .orange
    case "PICKED_UP":
        return .green
    case "IN_PROGRESS":
        return .blue
    case "APPROVED":
        return .teal
    case "CANCELLED", "CANCELED", "REJECTED", "DENIED", "FAILED":
        return .red
    case "PENDING_APPROVAL":
        return .orange
    default:
        return .gray
    }
}

private func progressTrackTint(for status: String) -> Color {
    switch normalizedOrderStatus(status) {
    case "CANCELLED", "CANCELED", "REJECTED", "DENIED", "FAILED":
        return Color.primary.opacity(0.10)
    default:
        return Color.primary.opacity(0.14)
    }
}

private func progressFillTint(for status: String) -> Color {
    switch normalizedOrderStatus(status) {
    case "CANCELLED", "CANCELED", "REJECTED", "DENIED", "FAILED":
        return .gray
    default:
        return statusTint(for: status)
    }
}

private func normalizedOrderStatus(_ status: String) -> String {
    status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

private enum OrderLiveActivityDebugLog {
    static func layout(
        family: String,
        orderCode: String,
        status: String,
        title: String,
        orderCodeDisplay: OrderLiveActivityOrderCodeDisplay,
        compactStatus: String
    ) {
#if DEBUG
        print("DEBUG [OrderLiveActivityLayout] render family=\(family) orderCode=\(orderCode) status=\(status) titleLength=\(title.count) orderCodeDisplay=\(orderCodeDisplay.text) compactStatus=\(compactStatus)")
        print("DEBUG [OrderLiveActivityLayout] textPolicy titleOriginalLength=\(title.count) titleDisplayLength=\(OrderLiveActivityTextPolicy.displayTitle(title, maxLength: 22).count) orderCodeMode=\(orderCodeDisplay.mode.rawValue)")
#endif
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
