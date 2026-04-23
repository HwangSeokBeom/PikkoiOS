import SwiftUI

struct CartRootView: View {
    @StateObject private var presenter: CartPresenter

    init(presenter: CartPresenter) {
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
        .pikkoScreen(title: presenter.viewState.title)
        .task {
            await presenter.send(.onAppear)
        }
    }
}
