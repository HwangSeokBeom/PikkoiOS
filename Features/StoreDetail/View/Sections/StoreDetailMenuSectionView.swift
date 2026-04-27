import SwiftUI

struct StoreDetailMenuSectionView: View {
    private enum Layout {
        static let menuImageSize: CGFloat = 98
        static let imageTextSpacing: CGFloat = 16
        static let textVerticalSpacing: CGFloat = 7
        static let addButtonMinWidth: CGFloat = 76
        static let addButtonHeight: CGFloat = 34
        static let quantityControlWidth: CGFloat = 116
        static let quantityControlHeight: CGFloat = 40
    }

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
                            appearance: selectedFilterID == filter.id ? .filled : .outlined,
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
        VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
            if let badgeText = menu.badgeText {
                Text(badgeText)
                    .font(PikkoTypography.micro)
                    .foregroundStyle(PikkoColor.sage500)
                    .padding(.horizontal, PikkoSpacing.xs)
                    .frame(height: 20)
                    .background(PikkoColor.surfaceMuted)
                    .clipShape(Capsule())
            }

            HStack(alignment: .top, spacing: Layout.imageTextSpacing) {
                VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
                    Text(menu.name)
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(PikkoColor.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(menu.description)
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Text(menu.priceText)
                        .font(PikkoTypography.title)
                        .foregroundStyle(PikkoColor.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.9)
                        .layoutPriority(2)

                    quantityControl(for: menu)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)

                menuImage(menu)
                    .layoutPriority(0)
            }
        }
        .frame(minHeight: Layout.menuImageSize, alignment: .top)
        .padding(.bottom, PikkoSpacing.lg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
    }

    private func menuImage(_ menu: StoreDetailMenuItem) -> some View {
        ZStack {
            AuthorizedAsyncImage(
                path: menu.imagePath,
                loader: imageLoader,
                contentMode: .fill,
                cornerRadius: PikkoRadius.card,
                showsProgress: false
            )
            .frame(width: Layout.menuImageSize, height: Layout.menuImageSize)
            .clipped()

            if menu.isSoldOut {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .fill(Color.black.opacity(0.34))
                    .frame(width: Layout.menuImageSize, height: Layout.menuImageSize)

                Text("품절")
                    .font(PikkoTypography.cardTitle)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Layout.menuImageSize, height: Layout.menuImageSize)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    @ViewBuilder
    private func quantityControl(for menu: StoreDetailMenuItem) -> some View {
        if menu.isSoldOut {
            Text("품절된 메뉴예요")
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
        } else if menu.quantity == 0 {
            addButton(action: { onIncrementTap(menu.id) })
        } else {
            HStack(spacing: PikkoSpacing.xs) {
                circleControl(systemImage: "minus", action: { onDecrementTap(menu.id) })

                Text("\(menu.quantity)")
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
                    .frame(minWidth: 20)

                circleControl(systemImage: "plus", action: { onIncrementTap(menu.id) })
            }
            .padding(.horizontal, PikkoSpacing.sm)
            .frame(width: Layout.quantityControlWidth, height: Layout.quantityControlHeight)
            .background(PikkoColor.surfaceMuted)
            .clipShape(Capsule())
        }
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PikkoSpacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))

                Text("담기")
                    .font(PikkoTypography.bodyStrong)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(PikkoColor.accentStrong)
            .padding(.horizontal, PikkoSpacing.md)
            .frame(minWidth: Layout.addButtonMinWidth)
            .frame(height: Layout.addButtonHeight)
            .background(.white)
            .overlay {
                RoundedRectangle(cornerRadius: Layout.addButtonHeight / 2, style: .continuous)
                    .stroke(PikkoColor.accent.opacity(0.35), lineWidth: 1)
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("메뉴 담기")
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
