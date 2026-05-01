import SwiftUI
import UIKit

struct HomeCategorySectionView: View {
    let categories: [HomeCategoryItem]
    let selectedCategoryID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(categories) { category in
                    Button {
                        onSelect(category.id)
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedCategoryID == category.id ? PikkoColor.sage50 : PikkoColor.gray100)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    HomeCategoryIcon(category: category)
                                        .frame(width: 28, height: 28)
                                }

                            Text(category.title)
                                .font(PikkoTypography.micro)
                                .foregroundStyle(selectedCategoryID == category.id ? PikkoColor.accentStrong : PikkoColor.secondaryText)
                        }
                        .frame(width: 62)
                        .padding(.vertical, 10)
                        .background(PikkoColor.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    selectedCategoryID == category.id ? PikkoColor.accent.opacity(0.45) : PikkoColor.line,
                                    lineWidth: selectedCategoryID == category.id ? 1.2 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PikkoSpacing.sm)
            .padding(.vertical, PikkoSpacing.sm)
        }
        .background(PikkoColor.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(PikkoColor.line.opacity(0.7), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                .foregroundStyle(PikkoColor.accentStrong)
                .accessibilityHidden(true)
        }
    }
}
