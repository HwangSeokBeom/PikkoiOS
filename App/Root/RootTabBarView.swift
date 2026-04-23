import SwiftUI

struct RootTabBarView: View {
    let selectedTab: RootTab
    let onSelect: (RootTab) -> Void
    let onQuickAction: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            FloatingQuickActionView(action: onQuickAction)
                .offset(y: -20)
                .zIndex(1)

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 26)

                HStack(spacing: 0) {
                    item(for: .home)
                    item(for: .order)
                    Color.clear
                        .frame(width: 88)
                    item(for: .community)
                    item(for: .profile)
                }
                .padding(.horizontal, PikkoSpacing.md)
                .padding(.top, PikkoSpacing.sm)
                .padding(.bottom, PikkoSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(tabBarBackground)
            }
        }
        .frame(height: 106)
    }

    private var tabBarBackground: some View {
        Rectangle()
            .fill(PikkoColor.surfaceElevated)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PikkoColor.line.opacity(0.8))
                    .frame(height: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: -2)
    }

    private func item(for tab: RootTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: isSelected ? tab.activeSystemImage : tab.inactiveSystemImage)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isSelected ? PikkoColor.accentStrong : PikkoColor.gray300)

                Text(tab.title)
                    .font(PikkoTypography.micro)
                    .foregroundStyle(isSelected ? PikkoColor.accentStrong : PikkoColor.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
