import SwiftUI

struct VideoListRootView: View {
    @StateObject private var presenter: VideoListPresenter
    @StateObject private var router: VideoListRouter
    private let imageLoader: any AuthorizedImageLoading
    private let fetchStreamUseCase: FetchVideoStreamUseCase
    private let setLikeUseCase: SetVideoLikeUseCase
    private let appConfiguration: AppConfiguration
    private let tokenStore: any TokenStore
    private let makeVideoPlayerView: (Video, @escaping (Video) -> Void) -> AnyView
    private let resetTrigger: Int

    init(
        presenter: VideoListPresenter,
        router: VideoListRouter,
        imageLoader: any AuthorizedImageLoading,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        appConfiguration: AppConfiguration,
        tokenStore: any TokenStore,
        makeVideoPlayerView: @escaping (Video, @escaping (Video) -> Void) -> AnyView,
        resetTrigger: Int = 0
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.fetchStreamUseCase = fetchStreamUseCase
        self.setLikeUseCase = setLikeUseCase
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
        self.makeVideoPlayerView = makeVideoPlayerView
        self.resetTrigger = resetTrigger
    }

    var body: some View {
        VideoListView(
            presenter: presenter,
            imageLoader: imageLoader,
            fetchStreamUseCase: fetchStreamUseCase,
            setLikeUseCase: setLikeUseCase,
            appConfiguration: appConfiguration,
            tokenStore: tokenStore,
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
