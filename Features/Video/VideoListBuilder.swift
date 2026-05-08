import SwiftUI

@MainActor
struct VideoListBuilder {
    private let videoRepository: VideoRepository
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let appConfiguration: AppConfiguration
    private let tokenStore: any TokenStore
    private let videoLiveActivityManager: VideoLiveActivityManaging
    private let makeVideoPlayerView: (Video, @escaping (Video) -> Void) -> AnyView

    init(
        videoRepository: VideoRepository,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading,
        appConfiguration: AppConfiguration,
        tokenStore: any TokenStore,
        videoLiveActivityManager: VideoLiveActivityManaging = NoopVideoLiveActivityService.shared,
        makeVideoPlayerView: @escaping (Video, @escaping (Video) -> Void) -> AnyView
    ) {
        self.videoRepository = videoRepository
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
        self.videoLiveActivityManager = videoLiveActivityManager
        self.makeVideoPlayerView = makeVideoPlayerView
    }

    func build(resetTrigger: Int = 0, isTabActive: Bool = true) -> VideoListRootView {
        let router = VideoListRouter()
        let interactor = VideoListInteractor(
            fetchVideosUseCase: FetchVideosUseCase(repository: videoRepository),
            setVideoLikeUseCase: SetVideoLikeUseCase(repository: videoRepository)
        )
        let presenter = VideoListPresenter(
            interactor: interactor,
            router: router,
            sessionStore: sessionStore,
            videoLiveActivityManager: videoLiveActivityManager
        )
        return VideoListRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            fetchStreamUseCase: FetchVideoStreamUseCase(repository: videoRepository),
            setLikeUseCase: SetVideoLikeUseCase(repository: videoRepository),
            appConfiguration: appConfiguration,
            tokenStore: tokenStore,
            makeVideoPlayerView: makeVideoPlayerView,
            resetTrigger: resetTrigger,
            isTabActive: isTabActive
        )
    }
}
