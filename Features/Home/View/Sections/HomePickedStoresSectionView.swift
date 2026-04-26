import SwiftUI

struct HomePickedStoresSectionView: View {
    let stores: [StoreCard.Model]
    let emptyMessage: String?
    let imageLoader: any AuthorizedImageLoading
    let onLikeTap: (String) -> Void
    let onStoreTap: (String) -> Void
    let onStoreAppear: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            SectionHeader(
                title: "내 주변 가게",
                actionTitle: "거리순",
                actionSystemImage: "line.3.horizontal.decrease",
                size: .compact
            )

            HStack(spacing: PikkoSpacing.xs) {
                TagChip(
                    title: "주변 매장",
                    systemImage: "location.circle.fill",
                    isSelected: true,
                    appearance: .filled,
                    size: .compact
                )
                TagChip(title: "실시간 거리", appearance: .subtle, size: .compact)
            }

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

    private func sectionFallbackView(message: String) -> some View {
        Text(message)
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PikkoSpacing.md)
            .background(PikkoColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PikkoColor.line.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var resolvedEmptyMessage: String {
        if emptyMessage != nil {
            return "가까운 매장을 준비 중이에요. 잠시 후 다시 확인해 주세요."
        }

        return "가까운 매장이 아직 없어요."
    }
}
