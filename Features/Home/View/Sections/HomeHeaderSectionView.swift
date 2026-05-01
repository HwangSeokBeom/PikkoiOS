import SwiftUI

struct HomeHeaderSectionView: View {
    let locationLabel: String
    @Binding var searchText: String
    let popularKeywords: [String]
    let notificationUnreadCount: Int
    let onLocationTap: () -> Void
    let onNotificationTap: () -> Void
    let onSearchSubmit: () -> Void
    let onPopularKeywordTap: (String) -> Void
    @State private var hasLoggedBellPlacement = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: PikkoSpacing.sm) {
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

                        Spacer(minLength: PikkoSpacing.xs)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                NotificationBellButton(
                    unreadCount: notificationUnreadCount,
                    action: onNotificationTap
                )
            }
            .frame(maxWidth: .infinity)

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
        .onAppear {
            guard !hasLoggedBellPlacement else { return }
            hasLoggedBellPlacement = true
            Logger(category: "NotificationBell").debugVerbose("[NotificationBell] configured placement=homeRightItem")
        }
    }

    private var popularKeywordItems: [(rank: Int, keyword: String)] {
        Array(popularKeywords.prefix(3).enumerated())
            .map { index, keyword in (index + 1, keyword) }
    }
}
