import SwiftUI

struct AuthRootView: View {
    @StateObject private var presenter: AuthPresenter

    init(presenter: AuthPresenter) {
        _presenter = StateObject(wrappedValue: presenter)
    }

    var body: some View {
        FeaturePlaceholderView(
            title: presenter.viewState.title,
            subtitle: presenter.viewState.subtitle,
            primaryActionTitle: presenter.viewState.primaryActionTitle,
            onPrimaryAction: {
                Task {
                    await presenter.send(.primaryButtonTapped)
                }
            }
        )
        .pikkoScreen(title: "Auth")
        .task {
            await presenter.send(.onAppear)
        }
    }
}
