import SwiftUI

struct HomeHeaderSectionView: View {
    let locationLabel: String
    @Binding var searchText: String
    let popularKeywords: [String]
    let onLocationTap: () -> Void
    let onSearchSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onLocationTap) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PikkoColor.gray600)

                    Text(locationLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PikkoColor.primaryText)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PikkoColor.gray500)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            SearchBar(
                text: $searchText,
                placeholder: "검색어를 입력해주세요.",
                onSubmit: onSearchSubmit,
                style: .compact
            )

            if !formattedPopularKeywords.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(PikkoColor.accentSoft)

                    Text("인기검색어")
                        .font(PikkoTypography.micro)
                        .foregroundStyle(PikkoColor.sage300)

                    Rectangle()
                        .fill(PikkoColor.line)
                        .frame(width: 1, height: 8)

                    Text(formattedPopularKeywords)
                        .font(PikkoTypography.micro)
                        .foregroundStyle(PikkoColor.sage500)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var formattedPopularKeywords: String {
        Array(popularKeywords.prefix(3).enumerated())
            .map { index, keyword in
                "\(index + 1) \(keyword)"
            }
            .joined(separator: "   ")
    }
}
