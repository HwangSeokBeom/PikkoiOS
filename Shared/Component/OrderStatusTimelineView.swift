import SwiftUI

struct OrderStatusTimelineView: View {
    enum StageState {
        case completed
        case current
        case upcoming
    }

    struct Stage: Identifiable {
        let id: String
        let title: String
        let timeText: String
        let state: StageState
    }

    let stages: [Stage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                HStack(alignment: .top, spacing: PikkoSpacing.sm) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(circleColor(for: stage.state))
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle()
                                    .stroke(circleBorderColor(for: stage.state), lineWidth: 2)
                            }
                            .overlay {
                                if stage.state != .upcoming {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }

                        if index < stages.count - 1 {
                            Rectangle()
                                .fill(lineColor(for: stage.state))
                                .frame(width: 2, height: 30)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.title)
                            .font(stage.state == .current ? PikkoTypography.bodyStrong : PikkoTypography.body)
                            .foregroundStyle(stage.state == .upcoming ? PikkoColor.gray400 : PikkoColor.primaryText)
                        Text(stage.timeText)
                            .font(PikkoTypography.caption)
                            .foregroundStyle(PikkoColor.secondaryText)
                    }
                    Spacer()
                }
            }
        }
    }

    private func circleColor(for state: StageState) -> Color {
        switch state {
        case .completed, .current:
            return PikkoColor.accent
        case .upcoming:
            return .white
        }
    }

    private func circleBorderColor(for state: StageState) -> Color {
        switch state {
        case .completed, .current:
            return PikkoColor.accent
        case .upcoming:
            return PikkoColor.gray300
        }
    }

    private func lineColor(for state: StageState) -> Color {
        switch state {
        case .completed, .current:
            return PikkoColor.accent.opacity(0.75)
        case .upcoming:
            return PikkoColor.gray200
        }
    }
}

#Preview {
    OrderStatusTimelineView(
        stages: [
            .init(id: "accepted", title: "승인대기", timeText: "오후 6:24", state: .completed),
            .init(id: "accepted2", title: "주문승인", timeText: "오후 6:27", state: .completed),
            .init(id: "prepare", title: "조리 중", timeText: "오후 6:36", state: .current),
            .init(id: "pickup", title: "픽업대기", timeText: "곧 준비돼요", state: .upcoming),
            .init(id: "done", title: "픽업완료", timeText: "수령 후 완료", state: .upcoming)
        ]
    )
    .padding()
    .background(PikkoColor.background)
}
