import SwiftUI

struct DistanceChipBar: View {
    struct Option: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let title: String
    let options: [Option]
    let selectedIndex: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let clampedIndex = min(max(selectedIndex, 0), max(options.count - 1, 0))
            let titleWidth: CGFloat = 88
            let titleSpacing: CGFloat = 16
            let segmentSpacing: CGFloat = 6
            let bubbleWidth: CGFloat = 52
            let availableWidth = max(
                geometry.size.width - titleWidth - titleSpacing - segmentSpacing * CGFloat(max(options.count - 1, 0)),
                40
            )
            let segmentWidth = availableWidth / CGFloat(max(options.count, 1))
            let trackStartX = titleWidth + titleSpacing
            let segmentVisualWidth = max(segmentWidth - 1, 10)
            let selectedCenterX = trackStartX + CGFloat(clampedIndex) * (segmentWidth + segmentSpacing) + segmentVisualWidth / 2
            let bubbleX = min(
                max(selectedCenterX - bubbleWidth / 2, trackStartX),
                max(geometry.size.width - bubbleWidth, trackStartX)
            )

            ZStack(alignment: .topLeading) {
                HStack(spacing: titleSpacing) {
                    TagChip(title: title, isSelected: true, appearance: .subtle)
                        .frame(width: titleWidth)
                        .padding(.top, 20)

                    HStack(spacing: segmentSpacing) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            Button {
                                onSelect?(index)
                            } label: {
                                Capsule(style: .continuous)
                                    .fill(index <= clampedIndex ? PikkoColor.accent.opacity(index == clampedIndex ? 1 : 0.42) : PikkoColor.gray200)
                                    .frame(width: segmentVisualWidth, height: 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 36)
                }
                .frame(height: 58)

                if !options.isEmpty {
                    Text(options[clampedIndex].title)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: bubbleWidth, height: 24)
                        .frame(height: 24)
                        .background(PikkoColor.accent)
                        .clipShape(Capsule())
                        .offset(x: bubbleX, y: 0)
                }
            }
        }
        .frame(height: 58)
    }
}

#Preview {
    DistanceChipBar(
        title: "Distance",
        options: [
            .init(id: "100", title: "100M"),
            .init(id: "300", title: "300M"),
            .init(id: "500", title: "500M"),
            .init(id: "1k", title: "1KM"),
            .init(id: "2k", title: "2KM"),
            .init(id: "3k", title: "3KM")
        ],
        selectedIndex: 1
    )
    .padding()
    .background(PikkoColor.background)
}
