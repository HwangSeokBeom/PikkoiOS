import AVFoundation
import SwiftUI

enum ShortsVideoAspectPolicy {
    static let defaultVideoGravity: AVLayerVideoGravity = .resizeAspect

    static func aspectFitFrame(contentSize: CGSize, containerSize: CGSize) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }
}

struct VideoListView: View {
    private enum ScrollAnchor {
        static let top = "video-scroll-top"
    }

    @ObservedObject var presenter: VideoListPresenter
    let imageLoader: any AuthorizedImageLoading
    let fetchStreamUseCase: FetchVideoStreamUseCase
    let setLikeUseCase: SetVideoLikeUseCase
    let appConfiguration: AppConfiguration
    let tokenStore: any TokenStore
    let resetTrigger: Int
    let isTabActive: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var visibleVideoID: String?

    var body: some View {
        ZStack {
            PikkoColor.background.ignoresSafeArea()

            if presenter.viewState.isLoading {
                LoadingView(message: "영상을 준비하고 있어요")
                    .padding(PikkoSpacing.xl)
            } else if presenter.viewState.showsErrorState {
                EmptyStateView(
                    title: "영상을 불러오지 못했어요.",
                    message: "잠시 후 다시 시도해 주세요.",
                    actionTitle: "재시도",
                    action: {
                        Task { await presenter.send(.retryTapped) }
                    }
                )
                .padding(PikkoSpacing.xl)
            } else if presenter.viewState.showsEmptyState {
                EmptyStateView(
                    title: "아직 등록된 영상이 없어요.",
                    message: "새로운 픽업 메뉴 영상이 등록되면 여기에서 확인할 수 있어요.",
                    actionTitle: nil,
                    action: nil
                )
                .padding(PikkoSpacing.xl)
            } else {
                content
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            Task { await presenter.send(.viewDisappeared(reason: presenter.viewState.pendingDisappearReason)) }
        }
        .onChange(of: scenePhase) { _, phase in
            Task { await presenter.send(.scenePhaseChanged(isActive: phase == .active)) }
            if phase == .background {
                PictureInPictureManager.shared.start(reason: "appBackgrounded")
            }
        }
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(ScrollAnchor.top)
                    if let errorMessage = presenter.viewState.errorMessage {
                        ToastView(message: errorMessage, tone: .warning)
                            .padding(.horizontal, PikkoSpacing.lg)
                            .padding(.top, PikkoSpacing.md)
                    }

                    ForEach(presenter.viewState.videos) { video in
                        ShortsVideoPageView(
                            model: video,
                            imageLoader: imageLoader,
                            fetchStreamUseCase: fetchStreamUseCase,
                            setLikeUseCase: setLikeUseCase,
                            appConfiguration: appConfiguration,
                            tokenStore: tokenStore,
                            isActive: presenter.viewState.activeShortsVideoID == video.id,
                            isPlaying: presenter.viewState.activeShortsVideoID == video.id && presenter.viewState.isShortsPlaying,
                            disappearReason: presenter.viewState.pendingDisappearReason,
                            onTap: {
                                Task { await presenter.send(.videoTapped(video.id)) }
                            },
                            onOriginalTap: {
                                Task { await presenter.send(.originalVideoTapped(video.id)) }
                            },
                            onLikeTap: {
                                Task { await presenter.send(.videoLikeTapped(video.id)) }
                            },
                            onPlaybackSnapshot: { snapshot in
                                Task { await presenter.send(.shortsPlaybackSnapshotUpdated(snapshot)) }
                            }
                        )
                        .containerRelativeFrame(.vertical)
                        .id(video.id)
                        .onAppear {
                            Task { await presenter.send(.videoAppeared(video.id)) }
                        }
                    }

                    if presenter.viewState.isPaging {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(PikkoColor.accentStrong)
                            Spacer()
                        }
                        .padding(.vertical, PikkoSpacing.md)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleVideoID)
            .onChange(of: visibleVideoID) { _, videoID in
                guard let videoID else { return }
                Task { await presenter.send(.visibleVideoChanged(videoID)) }
            }
            .onChange(of: resetTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(ScrollAnchor.top, anchor: .top)
                }
                Task { await presenter.send(.refreshRequested) }
            }
        }
    }
}

private struct ShortsVideoPageView: View {
    let model: VideoCardModel
    let imageLoader: any AuthorizedImageLoading
    let fetchStreamUseCase: FetchVideoStreamUseCase
    let setLikeUseCase: SetVideoLikeUseCase
    let appConfiguration: AppConfiguration
    let tokenStore: any TokenStore
    let isActive: Bool
    let isPlaying: Bool
    let disappearReason: VideoListViewDisappearReason
    let onTap: () -> Void
    let onOriginalTap: () -> Void
    let onLikeTap: () -> Void
    let onPlaybackSnapshot: (VideoLiveActivitySnapshot) -> Void

    @StateObject private var viewModel: VideoPlayerViewModel
    @State private var areControlsExpanded = false
    @State private var scrubberProgress: Double = 0
    @State private var isScrubbing = false
    @State private var controlsFadeTask: Task<Void, Never>?

    init(
        model: VideoCardModel,
        imageLoader: any AuthorizedImageLoading,
        fetchStreamUseCase: FetchVideoStreamUseCase,
        setLikeUseCase: SetVideoLikeUseCase,
        appConfiguration: AppConfiguration,
        tokenStore: any TokenStore,
        isActive: Bool,
        isPlaying: Bool,
        disappearReason: VideoListViewDisappearReason,
        onTap: @escaping () -> Void,
        onOriginalTap: @escaping () -> Void,
        onLikeTap: @escaping () -> Void,
        onPlaybackSnapshot: @escaping (VideoLiveActivitySnapshot) -> Void
    ) {
        self.model = model
        self.imageLoader = imageLoader
        self.fetchStreamUseCase = fetchStreamUseCase
        self.setLikeUseCase = setLikeUseCase
        self.appConfiguration = appConfiguration
        self.tokenStore = tokenStore
        self.isActive = isActive
        self.isPlaying = isPlaying
        self.disappearReason = disappearReason
        self.onTap = onTap
        self.onOriginalTap = onOriginalTap
        self.onLikeTap = onLikeTap
        self.onPlaybackSnapshot = onPlaybackSnapshot
        _viewModel = StateObject(
            wrappedValue: VideoPlayerViewModel(
                video: model.video,
                fetchStreamUseCase: fetchStreamUseCase,
                setLikeUseCase: setLikeUseCase,
                appConfiguration: appConfiguration,
                tokenStore: tokenStore,
                context: .shorts
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            mediaSurface

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: PikkoSpacing.md) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                        Text(model.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if !model.description.isEmpty {
                            Text(model.description)
                                .font(PikkoTypography.body)
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(3)
                        }

                        HStack(spacing: PikkoSpacing.xs) {
                            metaPill(systemImage: "clock.fill", text: model.durationText)
                            metaPill(systemImage: "eye.fill", text: model.viewCountText)
                            if !model.createdAtText.isEmpty {
                                metaPill(systemImage: "calendar", text: model.createdAtText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: PikkoSpacing.md) {
                        actionButton(
                            systemImage: model.isLiked ? "heart.fill" : "heart",
                            title: model.likeCountText,
                            isActive: model.isLiked,
                            action: onLikeTap
                        )
                        .disabled(model.isLikeUpdating)

                        actionButton(systemImage: "arrow.up.left.and.arrow.down.right", title: "원본", isActive: false, action: onOriginalTap)
                        actionButton(systemImage: "text.bubble.fill", title: "댓글", isActive: false, action: {})
                        actionButton(systemImage: "square.and.arrow.up", title: "공유", isActive: false, action: {})
                    }
                }
                .padding(.horizontal, PikkoSpacing.lg)
                .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset + PikkoSpacing.section)
            }

            shortsControls
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showControlsTemporarily()
            onTap()
        }
        .task(id: isActive) {
            if isActive {
                await viewModel.loadStreamIfNeeded()
                if isPlaying {
                    viewModel.play()
                } else {
                    viewModel.pause()
                }
            } else {
                viewModel.pause()
            }
        }
        .onChange(of: isPlaying) { _, shouldPlay in
            guard isActive else {
                viewModel.pause()
                return
            }
            if shouldPlay {
                viewModel.play()
            } else {
                viewModel.pause()
            }
            publishPlaybackSnapshot()
        }
        .onChange(of: viewModel.viewState.currentTime) { _, _ in
            guard isActive else { return }
            publishPlaybackSnapshot()
        }
        .onChange(of: viewModel.viewState.playbackState) { _, _ in
            guard isActive else { return }
            publishPlaybackSnapshot()
        }
        .onDisappear {
            if disappearReason == .openOriginal {
                viewModel.detachFromView(reason: "openOriginal")
            } else if disappearReason == .appBackground {
                Logger(category: "VideoList").debug("[VideoPlayback] continue reason=appBackgrounded videoId=\(model.id)")
            } else {
                viewModel.pause()
            }
            controlsFadeTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === viewModel.player?.currentItem else { return }
            if isPlaying {
                viewModel.replay()
            } else {
                viewModel.seek(toProgress: 0)
            }
        }
    }

    @ViewBuilder
    private var mediaSurface: some View {
        if let player = viewModel.player {
            VideoPlayerLayerView(
                player: player,
                videoGravity: ShortsVideoAspectPolicy.defaultVideoGravity,
                videoId: model.id,
                context: .shorts,
                isPictureInPictureEnabled: isActive
            )
                .ignoresSafeArea()
        } else {
            AuthorizedAsyncImage(
                path: model.thumbnailURL,
                loader: imageLoader,
                contentMode: .fill,
                cornerRadius: 0,
                showsProgress: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }

        LinearGradient(
            colors: [
                .black.opacity(0.1),
                .black.opacity(0.24),
                .black.opacity(0.78)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        switch viewModel.viewState.playbackState {
        case .loadingStream:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.9)
        case .ready, .paused:
            Image(systemName: "play.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(.black.opacity(0.45))
                .clipShape(Circle())
        case .failed, .expiredOrUnavailable:
            VStack(spacing: PikkoSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                Text("재생할 수 없어요")
                    .font(PikkoTypography.captionStrong)
            }
            .foregroundStyle(.white)
            .padding(PikkoSpacing.md)
            .background(.black.opacity(0.46))
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        case .idle, .playing:
            EmptyView()
        }
    }

    private var shortsControls: some View {
        VStack {
            Spacer()

            VStack(spacing: areControlsExpanded ? PikkoSpacing.xs : 3) {
                if areControlsExpanded || isScrubbing {
                    HStack(spacing: PikkoSpacing.sm) {
                        controlButton(systemImage: isPlaying ? "pause.fill" : "play.fill") {
                            onTap()
                            showControlsTemporarily()
                        }
                        controlButton(systemImage: "gobackward.10") {
                            viewModel.seek(by: -10)
                            showControlsTemporarily()
                        }

                        Text(VideoDurationFormatter.string(from: currentControlTime))
                            .font(PikkoTypography.micro)
                            .foregroundStyle(.white.opacity(0.88))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .leading)

                        Spacer(minLength: PikkoSpacing.xs)

                        Text(durationText)
                            .font(PikkoTypography.micro)
                            .foregroundStyle(.white.opacity(0.88))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)

                        controlButton(systemImage: "goforward.10") {
                            viewModel.seek(by: 10)
                            showControlsTemporarily()
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubberProgress : viewModel.viewState.playbackProgress },
                        set: { progress in
                            if !isScrubbing {
                                isScrubbing = true
                                viewModel.beginScrubbing()
                            }
                            scrubberProgress = progress
                            viewModel.updateScrubbing(progress: progress)
                            areControlsExpanded = true
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing {
                            isScrubbing = true
                            scrubberProgress = viewModel.viewState.playbackProgress
                            viewModel.beginScrubbing()
                            areControlsExpanded = true
                        } else {
                            viewModel.endScrubbing(progress: scrubberProgress)
                            isScrubbing = false
                            scheduleControlsFade()
                        }
                    }
                )
                .tint(PikkoColor.accent)
                .disabled(viewModel.viewState.duration == nil)
                .scaleEffect(x: 1, y: areControlsExpanded || isScrubbing ? 1 : 0.46, anchor: .center)
                .opacity(viewModel.viewState.duration == nil ? 0.45 : 1)
            }
            .padding(.horizontal, PikkoSpacing.lg)
            .padding(.vertical, areControlsExpanded || isScrubbing ? PikkoSpacing.sm : PikkoSpacing.xs)
            .background(.black.opacity(areControlsExpanded || isScrubbing ? 0.34 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.medium, style: .continuous))
            .padding(.horizontal, PikkoSpacing.lg)
            .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset + PikkoSpacing.sm)
        }
        .animation(.easeInOut(duration: 0.18), value: areControlsExpanded)
        .animation(.easeInOut(duration: 0.18), value: isScrubbing)
    }

    private func actionButton(systemImage: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.32))
                    .clipShape(Circle())
                Text(title)
                    .font(PikkoTypography.micro)
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? PikkoColor.primary : .white)
        }
        .buttonStyle(.plain)
    }

    private func controlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.16))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var currentControlTime: Double {
        if isScrubbing,
           let duration = viewModel.viewState.duration,
           duration.isFinite,
           duration > 0 {
            return duration * scrubberProgress
        }
        return viewModel.viewState.currentTime
    }

    private var durationText: String {
        guard let duration = viewModel.viewState.duration else { return "--:--" }
        return VideoDurationFormatter.string(from: duration)
    }

    private func showControlsTemporarily() {
        areControlsExpanded = true
        scheduleControlsFade()
    }

    private func scheduleControlsFade() {
        controlsFadeTask?.cancel()
        controlsFadeTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !isScrubbing {
                    areControlsExpanded = false
                }
            }
        }
    }

    private func metaPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(PikkoTypography.captionStrong)
        }
        .foregroundStyle(.white.opacity(0.84))
    }

    private func publishPlaybackSnapshot() {
        let state: VideoLiveActivityPlaybackState
        if isPlaying {
            state = .playing
        } else if case .playing = viewModel.viewState.playbackState {
            state = .playing
        } else {
            state = .paused
        }
        onPlaybackSnapshot(
            VideoLiveActivitySnapshot(
                videoId: model.id,
                title: model.title,
                thumbnailURLString: model.thumbnailURL,
                playbackState: state,
                elapsedTime: viewModel.viewState.currentTime,
                duration: viewModel.viewState.duration ?? model.video.duration,
                quality: viewModel.viewState.effectivePlaybackQuality ?? viewModel.viewState.userSelectedQuality
            )
        )
    }
}
