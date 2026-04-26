import SwiftUI

struct HomePopularStoresSectionView: View {
    let stores: [StoreCard.Model]
    let imageLoader: any AuthorizedImageLoading
    let onLikeTap: (String) -> Void
    let onStoreTap: (String) -> Void

    var body: some View {
        if !stores.isEmpty {
            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                SectionHeader(title: "실시간 인기 맛집", size: .compact)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PikkoSpacing.sm) {
                        ForEach(stores) { store in
                            StoreCard(
                                model: store,
                                loader: imageLoader,
                                style: .featured,
                                onLikeTapped: {
                                    onLikeTap(store.id)
                                }
                            )
                            .frame(width: 184)
                            .onTapGesture {
                                onStoreTap(store.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
