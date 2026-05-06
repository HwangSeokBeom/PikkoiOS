import SwiftUI

struct HomePickedStoresSectionView: View {
    let stores: [StoreCard.Model]
    let emptyMessage: String?
    let selectedTab: HomeNearbyStoreTab
    let distanceSortTitle: String
    let distanceSortSystemImage: String
    let imageLoader: any AuthorizedImageLoading
    let onTabTap: (HomeNearbyStoreTab) -> Void
    let onDistanceSortTap: () -> Void
    let onLikeTap: (String) -> Void
    let onStoreTap: (String) -> Void
    let onStoreAppear: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            SectionHeader(
                title: "내 주변 가게",
                actionTitle: distanceSortTitle,
                actionSystemImage: distanceSortSystemImage,
                action: onDistanceSortTap,
                size: .compact
            )

            HStack(spacing: PikkoSpacing.xs) {
                ForEach(HomeNearbyStoreTab.allCases, id: \.self) { tab in
                    let isSelected = selectedTab == tab

                    TagChip(
                        title: tab.title,
                        systemImage: tab.systemImage,
                        isSelected: isSelected,
                        appearance: isSelected ? .filled : .subtle,
                        action: {
                            onTabTap(tab)
                        },
                        size: .compact
                    )
                    .contentShape(Rectangle())
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .zIndex(2)

            if stores.isEmpty {
                sectionFallbackView(
                    message: resolvedEmptyMessage
                )
            } else {
                VStack(spacing: PikkoSpacing.sm) {
                    ForEach(stores) { store in
                        StoreCard(
                            model: store,
                            loader: imageLoader,
                            style: .list,
                            onCardTapped: {
                                onStoreTap(store.id)
                            },
                            onLikeTapped: {
                                onLikeTap(store.id)
                            }
                        )
                        .onAppear {
                            onStoreAppear(store.id)
                        }
                    }
                }
                .zIndex(0)
            }
        }
    }

    private func sectionFallbackView(message: String) -> some View {
        Text(message)
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PikkoSpacing.md)
            .background(PikkoColor.elevatedSurface)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.large, style: .continuous)
                    .stroke(PikkoColor.divider.opacity(0.65), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.large, style: .continuous))
    }

    private var resolvedEmptyMessage: String {
        if emptyMessage != nil {
            return "가까운 매장을 불러오지 못했어요. 잠시 후 다시 확인해 주세요."
        }

        return "가까운 매장이 아직 없어요."
    }
}
