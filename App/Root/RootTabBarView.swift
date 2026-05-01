import SwiftUI

enum RootTabBarMetrics {
    static let contentHeight: CGFloat = 72
    static let floatingOverlap: CGFloat = 22
    static let floatingCenterOverlap: CGFloat = floatingOverlap
    static let minimumContentGap: CGFloat = 28
    static let scrollContentBottomInset: CGFloat = contentHeight + floatingOverlap + minimumContentGap
}

struct RootTabBarView: View {
    private enum Layout {
        static let height: CGFloat = RootTabBarMetrics.contentHeight
        static let floatingTopOffset: CGFloat = -72
        static let floatingTrailingPadding: CGFloat = 18
        static let itemsTopPadding: CGFloat = 10
        static let itemsBottomPadding: CGFloat = 8
        static let itemHeight: CGFloat = 50
    }

    let selectedTab: RootTab
    let onSelect: (RootTab) -> Void
    let onQuickAction: () -> Void
    @State private var floatingButtonFrame: CGRect = .zero
    @State private var profileItemFrame: CGRect = .zero
    private let layoutLogger = Logger(category: "TabBarLayout")

    var body: some View {
        ZStack(alignment: .topTrailing) {
            tabBarBackground

            FloatingQuickActionView(action: onQuickAction)
                .padding(.trailing, Layout.floatingTrailingPadding)
                .offset(y: Layout.floatingTopOffset)
                .background(frameReader(FloatingButtonFramePreferenceKey.self))
                .zIndex(1)

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
        .coordinateSpace(name: "RootTabBarView")
        .onPreferenceChange(FloatingButtonFramePreferenceKey.self) { frame in
            floatingButtonFrame = frame
            logLayoutIfReady(floatingFrame: frame, profileFrame: profileItemFrame)
        }
        .onPreferenceChange(ProfileItemFramePreferenceKey.self) { frame in
            profileItemFrame = frame
            logLayoutIfReady(floatingFrame: floatingButtonFrame, profileFrame: frame)
        }
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
        .background(profileFrameReader(for: tab))
    }

    private func frameReader<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGRect {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.frame(in: .named("RootTabBarView")))
        }
    }

    @ViewBuilder
    private func profileFrameReader(for tab: RootTab) -> some View {
        if tab == .profile {
            frameReader(ProfileItemFramePreferenceKey.self)
        }
    }

    private func logLayoutIfReady(floatingFrame: CGRect, profileFrame: CGRect) {
        guard !floatingFrame.isEmpty, !profileFrame.isEmpty else { return }
        let adjustedFloatingFrame = floatingFrame.offsetBy(dx: 0, dy: Layout.floatingTopOffset)
        let overlapsProfile = adjustedFloatingFrame.intersects(profileFrame)
        layoutLogger.debug(
            "[TabBarLayout] adjusted floatingButton frame=\(adjustedFloatingFrame) profileItemFrame=\(profileFrame) overlapsProfile=\(overlapsProfile)"
        )
    }
}

private struct FloatingButtonFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ProfileItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
