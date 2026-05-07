import SwiftUI

enum RootTabBarMetrics {
    static let contentHeight: CGFloat = 68
    static let minimumContentGap: CGFloat = 12
    static let bottomOffset: CGFloat = 0
    static let safeAreaInsetSpacing: CGFloat = 0
    static let outerBottomPadding: CGFloat = 0
    static let maximumTotalHeight: CGFloat = contentHeight
    static let scrollContentBottomInset: CGFloat = contentHeight + minimumContentGap
    static let zIndex: Double = 100
}

struct RootTabBarLayoutMetrics: Equatable {
    let screenWidth: CGFloat
    let safeAreaBottom: CGFloat
    let horizontalInset: CGFloat
    let bottomOffset: CGFloat
    let safeAreaInsetSpacing: CGFloat
    let outerBottomPadding: CGFloat
    let tabBarHeight: CGFloat
    let innerVerticalPadding: CGFloat
    let contentBottomInset: CGFloat
    let isClipped: Bool
    let placement: String

    var totalHeight: CGFloat {
        tabBarHeight + outerBottomPadding
    }

    static func make(screenWidth: CGFloat, safeAreaBottom: CGFloat) -> RootTabBarLayoutMetrics {
        let horizontalInset: CGFloat = screenWidth <= 340 ? 16 : 20
        let contentWidth = max(screenWidth - horizontalInset * 2, 0)
        let isClipped = contentWidth <= 0 || horizontalInset < 16

        return RootTabBarLayoutMetrics(
            screenWidth: screenWidth,
            safeAreaBottom: safeAreaBottom,
            horizontalInset: horizontalInset,
            bottomOffset: RootTabBarMetrics.bottomOffset,
            safeAreaInsetSpacing: RootTabBarMetrics.safeAreaInsetSpacing,
            outerBottomPadding: RootTabBarMetrics.outerBottomPadding,
            tabBarHeight: RootTabBarMetrics.contentHeight,
            innerVerticalPadding: RootTabBarView.Layout.innerVerticalPadding,
            contentBottomInset: RootTabBarMetrics.scrollContentBottomInset,
            isClipped: isClipped,
            placement: "safeAreaInset"
        )
    }
}

struct RootTabBarView: View {
    enum Layout {
        static let height: CGFloat = RootTabBarMetrics.contentHeight
        static let innerVerticalPadding: CGFloat = 8
        static let itemHeight: CGFloat = 46
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

        ZStack {
            tabBarShadowBackground

            tabBarInnerBackground

            HStack(spacing: 0) {
                item(for: .home)
                item(for: .order)
                item(for: .video)
                item(for: .community)
                item(for: .profile)
            }
            .padding(.horizontal, PikkoSpacing.sm)
            .padding(.vertical, Layout.innerVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, metrics.horizontalInset)
        .frame(height: metrics.totalHeight)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .zIndex(RootTabBarMetrics.zIndex)
        .dynamicTypeSize(.xSmall ... .accessibility1)
        .onAppear {
            logLayout(metrics)
        }
        .onChange(of: metrics) { _, newMetrics in
            logLayout(newMetrics)
        }
    }

    private var tabBarShadowBackground: some View {
        RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous)
            .fill(PikkoColor.elevatedSurface.opacity(0.01))
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.itemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func logLayout(_ metrics: RootTabBarLayoutMetrics) {
        let logger = Logger(category: "TabBarLayout")
        logger.debug(
            "[TabBarLayout] screenWidth=\(Int(metrics.screenWidth)) safeAreaBottom=\(Int(metrics.safeAreaBottom)) tabBarHeight=\(Int(metrics.tabBarHeight)) horizontalInset=\(Int(metrics.horizontalInset)) bottomOffset=\(Int(metrics.bottomOffset)) safeAreaInsetSpacing=\(Int(metrics.safeAreaInsetSpacing))"
        )
        logger.debug(
            "[TabBarLayout] outerBottomPadding=\(Int(metrics.outerBottomPadding)) innerVerticalPadding=\(Int(metrics.innerVerticalPadding)) contentBottomInset=\(Int(metrics.contentBottomInset)) isClipped=\(metrics.isClipped)"
        )
        logger.debug(
            "[TabBarLayout] placement=\(metrics.placement) edge=bottom spacing=\(Int(metrics.safeAreaInsetSpacing))"
        )
    }
}
