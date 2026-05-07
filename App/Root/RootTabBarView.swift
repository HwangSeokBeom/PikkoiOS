import SwiftUI

enum RootTabBarMetrics {
    static let contentHeight: CGFloat = 66
    static let minimumContentGap: CGFloat = 14
    static let maximumBottomInset: CGFloat = 12
    static let maximumTotalHeight: CGFloat = contentHeight + maximumBottomInset
    static let scrollContentBottomInset: CGFloat = contentHeight + minimumContentGap
}

struct RootTabBarLayoutMetrics: Equatable {
    let screenWidth: CGFloat
    let safeAreaBottom: CGFloat
    let horizontalInset: CGFloat
    let bottomInset: CGFloat
    let computedHeight: CGFloat
    let isClipped: Bool

    var totalHeight: CGFloat {
        computedHeight + bottomInset
    }

    static func make(screenWidth: CGFloat, safeAreaBottom: CGFloat) -> RootTabBarLayoutMetrics {
        let horizontalInset: CGFloat = screenWidth <= 340 ? 16 : 18
        let bottomInset = min(max(safeAreaBottom * 0.45, 8), RootTabBarMetrics.maximumBottomInset)
        let contentWidth = max(screenWidth - horizontalInset * 2, 0)
        let isClipped = contentWidth <= 0 || horizontalInset < 16

        return RootTabBarLayoutMetrics(
            screenWidth: screenWidth,
            safeAreaBottom: safeAreaBottom,
            horizontalInset: horizontalInset,
            bottomInset: bottomInset,
            computedHeight: RootTabBarMetrics.contentHeight,
            isClipped: isClipped
        )
    }
}

struct RootTabBarView: View {
    private enum Layout {
        static let height: CGFloat = RootTabBarMetrics.contentHeight
        static let itemsTopPadding: CGFloat = 4
        static let itemsBottomPadding: CGFloat = 3
        static let itemHeight: CGFloat = 42
        static let iconFrame: CGFloat = 24
    }

    let selectedTab: RootTab
    let screenWidth: CGFloat
    let safeAreaBottom: CGFloat
    let onSelect: (RootTab) -> Void

    var body: some View {
        let metrics = RootTabBarLayoutMetrics.make(
            screenWidth: screenWidth,
            safeAreaBottom: safeAreaBottom
        )

        VStack(spacing: 0) {
            ZStack {
                tabBarShadowBackground
                    .padding(.horizontal, metrics.horizontalInset)

                tabBarInnerBackground
                    .padding(.horizontal, metrics.horizontalInset)

                HStack(spacing: 0) {
                    item(for: .home)
                    item(for: .order)
                    item(for: .video)
                    item(for: .community)
                    item(for: .profile)
                }
                .padding(.horizontal, metrics.horizontalInset + PikkoSpacing.sm)
                .padding(.top, Layout.itemsTopPadding)
                .padding(.bottom, Layout.itemsBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(height: metrics.computedHeight)

            Spacer(minLength: metrics.bottomInset)
        }
        .frame(height: metrics.totalHeight)
        .onAppear {
            logLayout(metrics)
        }
    }

    private var tabBarShadowBackground: some View {
        RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous)
            .fill(Color.clear)
            .pikkoShadow(PikkoShadow.floating)
    }

    private var tabBarInnerBackground: some View {
        RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous)
            .fill(PikkoColor.elevatedSurface.opacity(0.92))
            .background {
                RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous)
                    .stroke(PikkoColor.divider.opacity(0.55), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous))
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

    private func logLayout(_ metrics: RootTabBarLayoutMetrics) {
        Logger(category: "TabBar").debug(
            "[TabBar] layout screenWidth=\(Int(metrics.screenWidth)) safeAreaBottom=\(Int(metrics.safeAreaBottom)) horizontalInset=\(Int(metrics.horizontalInset)) bottomInset=\(Int(metrics.bottomInset)) computedHeight=\(Int(metrics.computedHeight)) isClipped=\(metrics.isClipped)"
        )
    }
}
