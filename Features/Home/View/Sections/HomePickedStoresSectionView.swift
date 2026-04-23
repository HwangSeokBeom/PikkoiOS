import SwiftUI

struct HomePickedStoresSectionView: View {
    let stores: [StoreCard.Model]
    let imageLoader: any AuthorizedImageLoading
    let onLikeTap: (String) -> Void
    let onStoreTap: (String) -> Void
    let onStoreAppear: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            SectionHeader(
                title: "내 주변 가게",
                actionTitle: "거리순",
                actionSystemImage: "line.3.horizontal.decrease",
                action: {}
            )

            HStack(spacing: PikkoSpacing.xs) {
                TagChip(
                    title: "주변 매장",
                    systemImage: "location.circle.fill",
                    isSelected: true,
                    appearance: .filled
                )
                TagChip(title: "실시간 거리", appearance: .subtle)
            }

            VStack(spacing: PikkoSpacing.lg) {
                ForEach(stores) { store in
                    StoreCard(
                        model: store,
                        loader: imageLoader,
                        style: .list,
                        onLikeTapped: {
                            onLikeTap(store.id)
                        }
                    )
                    .onAppear {
                        onStoreAppear(store.id)
                    }
                    .onTapGesture {
                        onStoreTap(store.id)
                    }
                }
            }
        }
    }
}
