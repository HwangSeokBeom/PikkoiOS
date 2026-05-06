import SwiftUI

enum RootTabBarMetrics {
    static let contentHeight: CGFloat = 60
    static let minimumContentGap: CGFloat = 22
    static let scrollContentBottomInset: CGFloat = contentHeight + minimumContentGap
}

struct RootTabBarView: View {
    private enum Layout {
        static let height: CGFloat = RootTabBarMetrics.contentHeight
        static let itemsTopPadding: CGFloat = 5
        static let itemsBottomPadding: CGFloat = 3
        static let itemHeight: CGFloat = 44
        static let iconFrame: CGFloat = 24
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
        RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous)
            .fill(PikkoColor.elevatedSurface.opacity(0.9))
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous)
                    .stroke(PikkoColor.divider.opacity(0.55), lineWidth: 1)
            }
            .padding(.horizontal, PikkoSpacing.lg)
            .padding(.bottom, PikkoSpacing.xs)
            .pikkoShadow(PikkoShadow.floating)
            .ignoresSafeArea(edges: .bottom)
    }

    private func item(for tab: RootTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.activeSystemImage : tab.inactiveSystemImage)
                    .font(.system(size: isSelected ? 18 : 17, weight: .semibold))
                    .foregroundStyle(isSelected ? PikkoColor.primary : PikkoColor.textTertiary)
                    .frame(width: Layout.iconFrame, height: Layout.iconFrame)

                Text(tab.title)
                    .font(PikkoTypography.micro)
                    .foregroundStyle(isSelected ? PikkoColor.primary : PikkoColor.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.itemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
