import SwiftUI
import UIKit

struct HomeCategorySectionView: View {
    let categories: [HomeCategoryItem]
    let selectedCategoryID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: PikkoSpacing.sm) {
                ForEach(categories) { category in
                    Button {
                        onSelect(category.id)
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: PikkoRadius.medium, style: .continuous)
                                .fill(selectedCategoryID == category.id ? PikkoColor.primarySoft : PikkoColor.gray100)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    HomeCategoryIcon(category: category)
                                        .frame(width: 28, height: 28)
                                }

                            Text(category.title)
                                .font(PikkoTypography.micro)
                                .foregroundStyle(selectedCategoryID == category.id ? PikkoColor.primaryPressed : PikkoColor.secondaryText)
                        }
                        .frame(width: 62)
                        .padding(.vertical, 10)
                        .background(selectedCategoryID == category.id ? PikkoColor.elevatedSurface : PikkoColor.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: PikkoRadius.large, style: .continuous)
                                .stroke(
                                    selectedCategoryID == category.id ? PikkoColor.primary.opacity(0.28) : PikkoColor.divider.opacity(0.75),
                                    lineWidth: selectedCategoryID == category.id ? 1.2 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.large, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PikkoSpacing.sm)
            .padding(.vertical, PikkoSpacing.sm)
        }
        .background(PikkoColor.elevatedSurface)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.divider.opacity(0.65), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }
}

private struct HomeCategoryIcon: View {
    let category: HomeCategoryItem

    var body: some View {
        if let uiImage = UIImage(named: category.imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: category.fallbackSystemImage)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(PikkoColor.primary)
                .accessibilityHidden(true)
        }
    }
}
