import SwiftUI

struct VideoListRootView: View {
    @StateObject private var presenter: VideoListPresenter
    @StateObject private var router: VideoListRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeVideoPlayerView: (Video, @escaping (Video) -> Void) -> AnyView
    private let resetTrigger: Int

    init(
        presenter: VideoListPresenter,
        router: VideoListRouter,
        imageLoader: any AuthorizedImageLoading,
        makeVideoPlayerView: @escaping (Video, @escaping (Video) -> Void) -> AnyView,
        resetTrigger: Int = 0
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeVideoPlayerView = makeVideoPlayerView
        self.resetTrigger = resetTrigger
    }

    var body: some View {
        VideoListView(
            presenter: presenter,
            imageLoader: imageLoader,
            resetTrigger: resetTrigger
        )
        .navigationDestination(isPresented: videoPresentedBinding) {
            if let video = router.pendingVideo {
                makeVideoPlayerView(video) { updatedVideo in
                    Task { await presenter.send(.videoUpdated(updatedVideo)) }
                }
            } else {
                EmptyView()
            }
        }
        .task {
            await presenter.send(.onAppear)
        }
    }

    private var videoPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.pendingVideo != nil },
            set: { isPresented in
                if !isPresented {
                    router.clearPendingRoute()
                }
            }
        )
    }
}
