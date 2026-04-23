import SwiftUI

struct HomeRootView: View {
    @StateObject private var presenter: HomePresenter
    private let imageLoader: any AuthorizedImageLoading

    init(
        presenter: HomePresenter,
        imageLoader: any AuthorizedImageLoading
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        self.imageLoader = imageLoader
    }

    var body: some View {
        HomeView(
            presenter: presenter,
            imageLoader: imageLoader
        )
        .task {
            await presenter.send(.onAppear)
        }
    }
}
