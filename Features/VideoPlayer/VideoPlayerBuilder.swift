import Foundation

@MainActor
struct VideoPlayerBuilder {
    private let video: Video
    private let fetchStreamUseCase: FetchVideoStreamUseCase
    private let setLikeUseCase: SetVideoLikeUseCase
    private let appConfiguration: AppConfiguration
    private let tokenStore: any TokenStore
    private let onVideoUpdated: (Video) -> Void

    init(
        video: Video,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        appConfiguration: AppConfiguration,
        tokenStore: any TokenStore,
        onVideoUpdated: @escaping (Video) -> Void
    ) {
        self.video = video
        self.fetchStreamUseCase = fetchStreamUseCase
        self.setLikeUseCase = setLikeUseCase
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
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
                onVideoUpdated: onVideoUpdated
            )
        )
    }
}
