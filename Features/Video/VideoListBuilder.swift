import SwiftUI

@MainActor
struct VideoListBuilder {
    private let videoRepository: VideoRepository
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeVideoPlayerView: (Video, @escaping (Video) -> Void) -> AnyView

    init(
        videoRepository: VideoRepository,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading,
        makeVideoPlayerView: @escaping (Video, @escaping (Video) -> Void) -> AnyView
    ) {
        self.videoRepository = videoRepository
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
        self.makeVideoPlayerView = makeVideoPlayerView
    }

    func build(resetTrigger: Int = 0) -> VideoListRootView {
        let router = VideoListRouter()
        let interactor = VideoListInteractor(
            fetchVideosUseCase: FetchVideosUseCase(repository: videoRepository),
            setVideoLikeUseCase: SetVideoLikeUseCase(repository: videoRepository)
        )
        let presenter = VideoListPresenter(
            interactor: interactor,
            router: router,
            sessionStore: sessionStore
        )
        return VideoListRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeVideoPlayerView: makeVideoPlayerView,
            resetTrigger: resetTrigger
        )
    }
}
