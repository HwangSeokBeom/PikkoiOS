import SwiftUI

struct CommunityFilterSectionView: View {
    let distanceOptions: [CommunityDistanceOption]
    let selectedDistanceID: String
    let sortOptions: [CommunitySortOption]
    let selectedSortID: String
    let filterChips: [CommunityFilterChip]
    let selectedFilterChipIDs: Set<String>
    let onDistanceSelect: (String) -> Void
    let onSortSelect: (String) -> Void
    let onFilterChipTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            DistanceChipBar(
                title: "Distance",
                options: distanceOptions.map { .init(id: $0.id, title: $0.title) },
                selectedIndex: selectedDistanceIndex,
                onSelect: { index in
                    guard distanceOptions.indices.contains(index) else { return }
                    onDistanceSelect(distanceOptions[index].id)
                }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PikkoSpacing.xs) {
                    ForEach(sortOptions) { option in
                        TagChip(
                            title: option.title,
                            systemImage: option.id == CommunitySortOption.latest.id ? "clock" : "line.3.horizontal.decrease.circle",
                            isSelected: selectedSortID == option.id,
                            appearance: selectedSortID == option.id ? .filled : .outlined,
                            action: {
                                onSortSelect(option.id)
                            }
                        )
                    }

                    ForEach(filterChips) { chip in
                        TagChip(
                            title: chip.title,
                            systemImage: chip.systemImage,
                            isSelected: selectedFilterChipIDs.contains(chip.id),
                            appearance: selectedFilterChipIDs.contains(chip.id) ? .filled : .outlined,
                            action: {
                                onFilterChipTap(chip.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var selectedDistanceIndex: Int {
        distanceOptions.firstIndex(where: { $0.id == selectedDistanceID }) ?? 0
    }
}

#Preview {
    CommunityFilterSectionView(
        distanceOptions: CommunityDistanceOption.all,
        selectedDistanceID: CommunityDistanceOption.defaultOption.id,
        sortOptions: CommunitySortOption.all,
        selectedSortID: CommunitySortOption.latest.id,
        filterChips: CommunityFilterChip.defaults,
        selectedFilterChipIDs: ["store", "video"],
        onDistanceSelect: { _ in },
        onSortSelect: { _ in },
        onFilterChipTap: { _ in }
    )
    .padding()
    .background(PikkoColor.background)
}
