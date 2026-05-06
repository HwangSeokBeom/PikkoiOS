import SwiftUI

struct RootTabContainerView<Content: View>: View {
    @Binding var path: NavigationPath

    let tab: RootTab
    let isActive: Bool
    @ViewBuilder let content: () -> Content
    @State private var didLogLifecycle = false

    var body: some View {
        NavigationStack(path: $path) {
            content()
        }
        .background(PikkoColor.background.ignoresSafeArea())
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
        .zIndex(isActive ? 1 : 0)
        .animation(nil, value: isActive)
        .onAppear {
            logLifecycleOnce()
        }
    }

    private func logLifecycleOnce() {
#if DEBUG
        guard !didLogLifecycle else { return }
        didLogLifecycle = true
        Logger(category: "TabRootLifecycle").debug("[TabRootLifecycle] tab=\(tab.rawValue) event=init")
#endif
    }
}
