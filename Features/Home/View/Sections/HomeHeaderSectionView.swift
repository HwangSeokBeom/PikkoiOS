import SwiftUI

struct HomeHeaderSectionView: View {
    let locationLabel: String
    @Binding var searchText: String
    let popularKeywords: [String]
    let onLocationTap: () -> Void
    let onSearchSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Button(action: onLocationTap) {
                HStack(spacing: PikkoSpacing.xs) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PikkoColor.gray600)

                    Text(locationLabel)
                        .font(PikkoTypography.section)
                        .foregroundStyle(PikkoColor.primaryText)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PikkoColor.gray500)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            SearchBar(
                text: $searchText,
                placeholder: "검색어를 입력해주세요.",
                onSubmit: onSearchSubmit
            )

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PikkoColor.accentSoft)

                Text("인기검색어")
                    .font(PikkoTypography.captionStrong)
                    .foregroundStyle(PikkoColor.accentSoft)

                if !popularKeywords.isEmpty {
                    Rectangle()
                        .fill(PikkoColor.line)
                        .frame(width: 1, height: 10)

                    ForEach(Array(popularKeywords.prefix(3).enumerated()), id: \.offset) { index, keyword in
                        Text("\(index + 1) \(keyword)")
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.sage500)
                    }
                }
            }
        }
    }
}
