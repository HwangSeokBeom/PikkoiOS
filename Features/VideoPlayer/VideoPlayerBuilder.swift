import Foundation

@MainActor
struct VideoPlayerBuilder {
    private let video: Video
    private let fetchStreamUseCase: FetchVideoStreamUseCase
    private let setLikeUseCase: SetVideoLikeUseCase
    private let appConfiguration: AppConfiguration
    private let tokenStore: any TokenStore
    private let imageLoader: any AuthorizedImageLoading
    private let context: VideoPlaybackContext
    private let onVideoUpdated: (Video) -> Void

    init(
        video: Video,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        appConfiguration: AppConfiguration,
        tokenStore: any TokenStore,
        imageLoader: any AuthorizedImageLoading,
        context: VideoPlaybackContext = .detail,
        onVideoUpdated: @escaping (Video) -> Void
    ) {
        self.video = video
        self.fetchStreamUseCase = fetchStreamUseCase
        self.setLikeUseCase = setLikeUseCase
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
        self.imageLoader = imageLoader
        self.context = context
        self.onVideoUpdated = onVideoUpdated
    }

    func build() -> VideoPlayerView {
        VideoPlayerView(
            viewModel: VideoPlayerViewModel(
                video: video,
                fetchStreamUseCase: fetchStreamUseCase,
                setLikeUseCase: setLikeUseCase,
                appConfiguration: appConfiguration,
                tokenStore: tokenStore,
                imageLoader: imageLoader,
                context: context,
                onVideoUpdated: onVideoUpdated
            )
        )
    }
}
