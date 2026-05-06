import SwiftUI

enum RootTabBarMetrics {
    static let contentHeight: CGFloat = 72
    static let minimumContentGap: CGFloat = 28
    static let scrollContentBottomInset: CGFloat = contentHeight + minimumContentGap
}

struct RootTabBarView: View {
    private enum Layout {
        static let height: CGFloat = RootTabBarMetrics.contentHeight
        static let itemsTopPadding: CGFloat = 10
        static let itemsBottomPadding: CGFloat = 8
        static let itemHeight: CGFloat = 50
    }

    let selectedTab: RootTab
    let onSelect: (RootTab) -> Void

    var body: some View {
        ZStack {
            tabBarBackground

            HStack(spacing: 0) {
                item(for: .home)
                item(for: .order)
                item(for: .video)
                item(for: .community)
                item(for: .profile)
            }
            .padding(.horizontal, PikkoSpacing.sm)
            .padding(.top, Layout.itemsTopPadding)
            .padding(.bottom, Layout.itemsBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: Layout.height)
    }

    private var tabBarBackground: some View {
        Rectangle()
            .fill(Color.white.opacity(0.86))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PikkoColor.line.opacity(0.8))
                    .frame(height: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: -2)
            .ignoresSafeArea(edges: .bottom)
    }

    private func item(for tab: RootTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.activeSystemImage : tab.inactiveSystemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? PikkoColor.accentStrong : PikkoColor.gray400)

                Text(tab.title)
                    .font(PikkoTypography.micro)
                    .foregroundStyle(isSelected ? PikkoColor.accentStrong : PikkoColor.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.itemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
