import SwiftUI

struct CommunityFilterSectionView: View {
    let distanceOptions: [CommunityDistanceOption]
    let selectedDistanceID: String
    let sortCategories: [CommunitySortCategory]
    let selectedSortCategoryID: String
    let filterChips: [CommunityFilterChip]
    let selectedFilterChipIDs: Set<String>
    let onDistanceSelect: (String) -> Void
    let onSortCategoryTap: (String) -> Void
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
                    ForEach(sortCategories) { category in
                        TagChip(
                            title: category.title,
                            systemImage: category.systemImage,
                            isSelected: selectedSortCategoryID == category.id,
                            appearance: selectedSortCategoryID == category.id ? .filled : .outlined,
                            action: {
                                onSortCategoryTap(category.id)
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
                .padding(.trailing, PikkoSpacing.xl)
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
        sortCategories: CommunitySortCategory.allCases,
        selectedSortCategoryID: CommunitySort.latest.category.id,
        filterChips: CommunityFilterChip.defaults,
        selectedFilterChipIDs: ["store", "video"],
        onDistanceSelect: { _ in },
        onSortCategoryTap: { _ in },
        onFilterChipTap: { _ in }
    )
    .padding()
    .background(PikkoColor.background)
}
