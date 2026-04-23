import SwiftUI

struct HomePopularStoresSectionView: View {
    let stores: [StoreCard.Model]
    let imageLoader: any AuthorizedImageLoading
    let onLikeTap: (String) -> Void
    let onStoreTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            SectionHeader(title: "실시간 인기 맛집")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PikkoSpacing.md) {
                    ForEach(stores) { store in
                        StoreCard(
                            model: store,
                            loader: imageLoader,
                            style: .featured,
                            onLikeTapped: {
                                onLikeTap(store.id)
                            }
                        )
                        .frame(width: 278)
                        .onTapGesture {
                            onStoreTap(store.id)
                        }
                    }
                }
                .padding(.trailing, PikkoSpacing.md)
            }
        }
    }
}
