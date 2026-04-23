import SwiftUI

struct RootTabContainerView<Content: View>: View {
    @Binding var path: NavigationPath

    let isActive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack(path: $path) {
            content()
        }
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
        .zIndex(isActive ? 1 : 0)
    }
}
