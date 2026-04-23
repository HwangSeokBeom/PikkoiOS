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
            let titleWidth: CGFloat = 82
            let spacing: CGFloat = 6
            let availableWidth = max(geometry.size.width - titleWidth - spacing * CGFloat(max(options.count - 1, 0)), 40)
            let segmentWidth = availableWidth / CGFloat(max(options.count, 1))

            ZStack(alignment: .topLeading) {
                HStack(spacing: spacing) {
                    TagChip(title: title, isSelected: true, appearance: .subtle)
                        .frame(width: titleWidth)

                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            onSelect?(index)
                        } label: {
                            Capsule(style: .continuous)
                                .fill(index <= clampedIndex ? PikkoColor.accent.opacity(index == clampedIndex ? 1 : 0.42) : PikkoColor.gray200)
                                .frame(width: max(segmentWidth - 1, 10), height: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 48)

                if !options.isEmpty {
                    Text(options[clampedIndex].title)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PikkoSpacing.xs)
                        .frame(height: 24)
                        .background(PikkoColor.accent)
                        .clipShape(Capsule())
                        .offset(
                            x: titleWidth + CGFloat(clampedIndex) * (segmentWidth + spacing) + max(segmentWidth - 1, 10) / 2 - 26,
                            y: -4
                        )
                }
            }
        }
        .frame(height: 48)
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
