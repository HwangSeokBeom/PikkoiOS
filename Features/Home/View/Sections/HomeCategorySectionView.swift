import SwiftUI

struct HomeCategorySectionView: View {
    let categories: [HomeCategoryItem]
    let selectedCategoryID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PikkoSpacing.sm) {
                ForEach(categories) { category in
                    Button {
                        onSelect(category.id)
                    } label: {
                        VStack(spacing: PikkoSpacing.xs) {
                            RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                                .fill(PikkoColor.gray100)
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Text(category.icon)
                                        .font(.system(size: 28))
                                }

                            Text(category.title)
                                .font(PikkoTypography.caption)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }
                        .frame(width: 72)
                        .padding(.vertical, PikkoSpacing.sm)
                        .background(PikkoColor.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                                .stroke(
                                    selectedCategoryID == category.id ? PikkoColor.accent.opacity(0.6) : PikkoColor.line,
                                    lineWidth: selectedCategoryID == category.id ? 1.5 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PikkoSpacing.xl)
            .padding(.vertical, PikkoSpacing.md)
        }
        .background(PikkoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 0)
    }
}
