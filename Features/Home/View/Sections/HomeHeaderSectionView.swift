import SwiftUI

struct HomeHeaderSectionView: View {
    let locationLabel: String
    @Binding var searchText: String
    let popularKeywords: [String]
    let onLocationTap: () -> Void
    let onSearchSubmit: () -> Void
    let onPopularKeywordTap: (String) -> Void

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
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            SearchBar(
                text: $searchText,
                placeholder: "검색어를 입력해주세요.",
                onSubmit: onSearchSubmit,
                style: .compact
            )

            if !popularKeywordItems.isEmpty {
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(popularKeywordItems, id: \.keyword) { item in
                                Button {
                                    onPopularKeywordTap(item.keyword)
                                } label: {
                                    Text("\(item.rank) \(item.keyword)")
                                        .font(PikkoTypography.micro)
                                        .foregroundStyle(PikkoColor.sage500)
                                        .lineLimit(1)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var popularKeywordItems: [(rank: Int, keyword: String)] {
        Array(popularKeywords.prefix(3).enumerated())
            .map { index, keyword in (index + 1, keyword) }
    }
}
