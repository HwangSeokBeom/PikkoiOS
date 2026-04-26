import SwiftUI

struct StoreDetailMenuSectionView: View {
    let menuFilters: [StoreDetailMenuFilter]
    let selectedFilterID: String
    let sections: [StoreDetailMenuSection]
    let imageLoader: any AuthorizedImageLoading
    let onFilterTap: (String) -> Void
    let onIncrementTap: (String) -> Void
    let onDecrementTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PikkoSpacing.xs) {
                    ForEach(menuFilters) { filter in
                        TagChip(
                            title: filter.title,
                            systemImage: filter.systemImage,
                            isSelected: selectedFilterID == filter.id,
                            appearance: .outlined,
                            action: {
                                onFilterTap(filter.id)
                            }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: PikkoSpacing.xxl) {
                if sections.isEmpty {
                    EmptyStateView(
                        title: "표시할 메뉴가 없어요",
                        message: "다른 필터를 선택하거나 잠시 후 다시 시도해주세요.",
                        systemImage: "fork.knife.circle"
                    )
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: PikkoSpacing.md) {
                        SectionHeader(
                            title: section.title,
                            subtitle: section.subtitle
                        )

                        VStack(spacing: PikkoSpacing.lg) {
                            ForEach(section.items) { menu in
                                menuRow(menu)
                            }
                        }
                    }
                }
            }
        }
    }

    private func menuRow(_ menu: StoreDetailMenuItem) -> some View {
        HStack(alignment: .top, spacing: PikkoSpacing.md) {
            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                if let badgeText = menu.badgeText {
                    Text(badgeText)
                        .font(PikkoTypography.micro)
                        .foregroundStyle(PikkoColor.sage500)
                        .padding(.horizontal, PikkoSpacing.xs)
                        .frame(height: 20)
                        .background(PikkoColor.surfaceMuted)
                        .clipShape(Capsule())
                }

                Text(menu.name)
                    .font(PikkoTypography.cardTitle)
                    .foregroundStyle(PikkoColor.primaryText)
                    .multilineTextAlignment(.leading)

                Text(menu.description)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Text(menu.priceText)
                    .font(PikkoTypography.title)
                    .foregroundStyle(PikkoColor.primaryText)

                quantityControl(for: menu)
            }

            Spacer(minLength: PikkoSpacing.md)

            ZStack {
                AuthorizedAsyncImage(
                    path: menu.imagePath,
                    loader: imageLoader,
                    contentMode: .fill,
                    cornerRadius: PikkoRadius.card,
                    showsProgress: false
                )
                .frame(width: 102, height: 102)

                if menu.isSoldOut {
                    RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                        .fill(Color.black.opacity(0.34))
                        .frame(width: 102, height: 102)

                    Text("품절")
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.bottom, PikkoSpacing.lg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func quantityControl(for menu: StoreDetailMenuItem) -> some View {
        if menu.isSoldOut {
            Text("품절된 메뉴예요")
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
        } else if menu.quantity == 0 {
            SecondaryButton(
                title: "담기",
                systemImage: "plus",
                action: { onIncrementTap(menu.id) }
            )
            .frame(maxWidth: 112)
        } else {
            HStack(spacing: PikkoSpacing.sm) {
                circleControl(systemImage: "minus", action: { onDecrementTap(menu.id) })

                Text("\(menu.quantity)")
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
                    .frame(minWidth: 20)

                circleControl(systemImage: "plus", action: { onIncrementTap(menu.id) })
            }
            .padding(.horizontal, PikkoSpacing.sm)
            .frame(height: 40)
            .background(PikkoColor.surfaceMuted)
            .clipShape(Capsule())
        }
    }

    private func circleControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PikkoColor.accentStrong)
                .frame(width: 28, height: 28)
                .background(.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
