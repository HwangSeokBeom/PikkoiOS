import AVFoundation
import AVKit
import SwiftUI

struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: VideoPlayerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            PikkoColor.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                    playerSurface
                    videoInfo
                    qualitySection
                }
                .padding(.horizontal, PikkoSpacing.lg)
                .padding(.top, PikkoSpacing.md)
                .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset)
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage = viewModel.viewState.toastMessage {
                ToastView(message: toastMessage, tone: .warning)
                    .padding(PikkoSpacing.lg)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run { viewModel.clearToast() }
                        }
                    }
            }
        }
        .overlay {
            ZStack {
                qualityBottomSheet
                subtitleBottomSheet
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: viewModel.viewState.isQualityMenuPresented)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: viewModel.viewState.isSubtitleMenuPresented)
        .task {
            await viewModel.loadStreamIfNeeded()
        }
        .onDisappear {
            viewModel.tearDown()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === viewModel.player?.currentItem else { return }
            viewModel.handlePlaybackFailure()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled)) { notification in
            guard notification.object as? AVPlayerItem === viewModel.player?.currentItem else { return }
            viewModel.handlePlaybackStalled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard notification.object as? AVPlayerItem === viewModel.player?.currentItem else { return }
            viewModel.handlePlaybackEnded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemNewErrorLogEntry)) { notification in
            guard notification.object as? AVPlayerItem === viewModel.player?.currentItem else { return }
            viewModel.logCurrentItemErrorLog()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemNewAccessLogEntry)) { notification in
            guard notification.object as? AVPlayerItem === viewModel.player?.currentItem else { return }
            viewModel.logCurrentItemAccessLog()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    viewModel.handleBackTapped()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .pikkoScreen(title: "영상")
        .onAppear {
            viewModel.logNavigationRender()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                PictureInPictureManager.shared.start(reason: "appBackgrounded")
            }
        }
    }

    private var playerSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .fill(.black)

            if let player = viewModel.player {
                VideoPlayerLayerView(
                    player: player,
                    videoId: viewModel.viewState.video.videoId,
                    context: .detail,
                    isPictureInPictureEnabled: true
                )
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            }

            overlayContent
            captionOverlay
            playbackControlBar
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.line.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: viewModel.viewState.playbackState)
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch viewModel.viewState.playbackState {
        case .idle:
            EmptyView()
        case .loadingStream:
            playerLoadingOverlay
                .transition(.opacity)
        case .ready, .paused:
            Button {
                viewModel.play()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        case .playing:
            EmptyView()
        case .failed:
            retryOverlay(buttonTitle: "재시도")
        case .expiredOrUnavailable:
            retryOverlay(buttonTitle: "재시도")
        }
    }

    @ViewBuilder
    private var playbackControlBar: some View {
        switch viewModel.viewState.playbackState {
        case .ready, .playing, .paused:
            VStack {
                Spacer()
                VStack(spacing: 6) {
                    HStack(spacing: PikkoSpacing.xs) {
                        Button {
                            if case .playing = viewModel.viewState.playbackState {
                                viewModel.pause()
                            } else {
                                viewModel.play()
                            }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.16))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPlaying ? "일시정지" : "재생")

                        Text(VideoDurationFormatter.string(from: viewModel.viewState.currentTime))
                            .font(PikkoTypography.micro)
                            .foregroundStyle(.white.opacity(0.86))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { viewModel.viewState.playbackProgress },
                                set: { progress in
                                    viewModel.seek(toProgress: progress)
                                }
                            ),
                            in: 0...1
                        )
                        .tint(PikkoColor.accent)
                        .disabled(viewModel.viewState.duration == nil)
                        .accessibilityLabel("재생 진행률")

                        Text(durationText)
                            .font(PikkoTypography.micro)
                            .foregroundStyle(.white.opacity(0.86))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)

                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                                viewModel.openSubtitleMenu()
                            }
                        } label: {
                            Image(systemName: "captions.bubble")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(viewModel.viewState.captionsEnabled ? .white : .white.opacity(0.45))
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.16))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.viewState.hasSubtitleOptions)
                        .accessibilityLabel(viewModel.viewState.hasSubtitleOptions ? "자막 선택" : "자막 없음")
                    }
                }
                .padding(.horizontal, PikkoSpacing.sm)
                .padding(.top, PikkoSpacing.xs)
                .padding(.bottom, PikkoSpacing.xs)
                .background(
                    LinearGradient(
                        colors: [
                            .black.opacity(0),
                            .black.opacity(0.62),
                            .black.opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        case .idle, .loadingStream, .failed, .expiredOrUnavailable:
            EmptyView()
        }
    }

    @ViewBuilder
    private var captionOverlay: some View {
        if viewModel.viewState.captionsEnabled,
           let text = viewModel.viewState.activeCaptionText,
           !text.isEmpty {
            VStack {
                Spacer()
                Text(text)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, PikkoSpacing.md)
                    .padding(.vertical, PikkoSpacing.xs)
                    .background(.black.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                    .padding(.horizontal, PikkoSpacing.lg)
                    .padding(.bottom, 58)
                    .accessibilityLabel("자막 \(text)")
            }
            .transition(.opacity)
        }
    }

    private var playerLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.34)

            VStack(spacing: PikkoSpacing.xs) {
                ProgressView()
                    .tint(PikkoColor.accent)
                    .scaleEffect(0.95)

                Text("영상을 준비 중입니다")
                    .font(PikkoTypography.captionStrong)
                    .foregroundStyle(.white.opacity(0.9))

                Text("스트리밍 정보를 불러오고 있어요")
                    .font(PikkoTypography.micro)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, PikkoSpacing.md)
            .padding(.vertical, PikkoSpacing.sm)
            .background(.black.opacity(0.28))
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(PikkoColor.accentSoft.opacity(0.22), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoInfo: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text(viewModel.viewState.video.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PikkoColor.primaryText)
                .lineLimit(2)

            Text(viewModel.viewState.video.description)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: PikkoSpacing.sm) {
                infoPill(systemImage: "clock.fill", text: VideoDurationFormatter.string(from: viewModel.viewState.video.duration))
                infoPill(systemImage: "eye.fill", text: "\(viewModel.viewState.video.viewCount)")
                infoPill(systemImage: "heart.fill", text: "\(viewModel.viewState.video.likeCount)")
            }

            Button {
                Task { await viewModel.toggleLike() }
            } label: {
                HStack(spacing: PikkoSpacing.xs) {
                    Image(systemName: viewModel.viewState.video.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                    Text(viewModel.viewState.video.isLiked ? "좋아요 취소" : "좋아요")
                        .font(PikkoTypography.bodyStrong)
                }
                .foregroundStyle(viewModel.viewState.video.isLiked ? PikkoColor.primary : PikkoColor.primaryPressed)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(PikkoColor.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                        .stroke(PikkoColor.divider.opacity(0.7), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.viewState.isLikeUpdating)
        }
    }

    @ViewBuilder
    private var qualitySection: some View {
        if let stream = viewModel.viewState.stream {
            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                SectionHeader(
                    title: "재생 옵션",
                    actionTitle: viewModel.viewState.qualityTitle,
                    actionSystemImage: "chevron.down",
                    action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            viewModel.openQualityMenu()
                        }
                    },
                    size: .compact
                )

                HStack(spacing: PikkoSpacing.xs) {
                    qualityButton(title: "자동", isSelected: isAutoQualitySelected) {
                        Task { await viewModel.selectQuality(nil, source: .chip) }
                    }

                    ForEach(stream.qualities) { quality in
                        qualityButton(title: quality.quality, isSelected: isQualitySelected(quality.quality)) {
                            Task { await viewModel.selectQuality(quality, source: .chip) }
                        }
                    }
                }

                HStack(spacing: PikkoSpacing.xs) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            viewModel.openSubtitleMenu()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "captions.bubble")
                                .font(.system(size: 12, weight: .semibold))
                            Text(viewModel.viewState.hasSubtitleOptions ? viewModel.viewState.selectedSubtitleTitle : "자막 없음")
                                .font(PikkoTypography.captionStrong)
                        }
                        .foregroundStyle(viewModel.viewState.hasSubtitleOptions ? PikkoColor.secondaryText : PikkoColor.gray400)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(PikkoColor.surfaceMuted)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.viewState.hasSubtitleOptions)

                    if viewModel.viewState.isSubtitleLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if let subtitleError = viewModel.viewState.subtitleErrorMessage {
                    Text(subtitleError)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.warning)
                }
            }
        }
    }

    private func retryOverlay(buttonTitle: String) -> some View {
        VStack(spacing: PikkoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(PikkoColor.warning)

            Text("영상을 재생할 수 없습니다.")
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("잠시 후 다시 시도해주세요.")
                .font(PikkoTypography.caption)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.retryStream() }
            } label: {
                Text(buttonTitle)
                    .font(PikkoTypography.captionStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, PikkoSpacing.md)
                    .padding(.vertical, PikkoSpacing.xs)
                    .background(PikkoColor.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(PikkoSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.62))
    }

    private func infoPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(PikkoTypography.captionStrong)
        }
        .foregroundStyle(PikkoColor.secondaryText)
    }

    private func qualityButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(isSelected ? .white : PikkoColor.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? PikkoColor.primary : PikkoColor.primarySoft)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var qualityBottomSheet: some View {
        if viewModel.viewState.isQualityMenuPresented {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            viewModel.dismissQualityMenu()
                        }
                    }

                VStack(alignment: .leading, spacing: 0) {
                    Text("화질 선택")
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.primaryText)
                        .padding(.horizontal, PikkoSpacing.lg)
                        .padding(.top, PikkoSpacing.lg)
                        .padding(.bottom, PikkoSpacing.sm)

                    qualitySheetButton(title: "자동", isSelected: isAutoQualitySelected) {
                        Task { await viewModel.selectQuality(nil, source: .actionSheet) }
                    }

                    if let stream = viewModel.viewState.stream {
                        ForEach(stream.qualities) { quality in
                            qualitySheetButton(
                                title: quality.quality,
                                isSelected: isQualitySelected(quality.quality)
                            ) {
                                Task { await viewModel.selectQuality(quality, source: .actionSheet) }
                            }
                        }
                    }
                }
                .safeAreaPadding(.bottom, PikkoSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PikkoColor.background)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: -6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func qualitySheetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PikkoSpacing.sm) {
                Text(title)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.primaryText)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PikkoColor.accentStrong)
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, PikkoSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var subtitleBottomSheet: some View {
        if viewModel.viewState.isSubtitleMenuPresented {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            viewModel.dismissSubtitleMenu()
                        }
                    }

                VStack(alignment: .leading, spacing: 0) {
                    Text("자막")
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.primaryText)
                        .padding(.horizontal, PikkoSpacing.lg)
                        .padding(.top, PikkoSpacing.lg)
                        .padding(.bottom, PikkoSpacing.sm)

                    subtitleSheetButton(
                        title: "끔",
                        isSelected: !viewModel.viewState.captionsEnabled
                    ) {
                        Task { await viewModel.selectSubtitle(nil) }
                    }

                    if viewModel.viewState.hasSystemSubtitleTracks {
                        subtitleSheetButton(
                            title: "시스템 자막",
                            isSelected: viewModel.viewState.captionsEnabled
                                && viewModel.viewState.selectedSubtitleID == nil
                        ) {
                            Task { await viewModel.selectSystemSubtitles() }
                        }
                    }

                    if let stream = viewModel.viewState.stream {
                        ForEach(stream.subtitles) { subtitle in
                            subtitleSheetButton(
                                title: "\(subtitle.name) · \(subtitle.languageCode)",
                                isSelected: viewModel.viewState.captionsEnabled
                                    && viewModel.viewState.selectedSubtitleID == subtitle.id
                            ) {
                                Task { await viewModel.selectSubtitle(subtitle) }
                            }
                        }
                    }
                }
                .safeAreaPadding(.bottom, PikkoSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PikkoColor.background)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: -6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func subtitleSheetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: PikkoSpacing.sm) {
                Text(title)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.primaryText)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PikkoColor.accentStrong)
                }
            }
            .frame(minHeight: 48)
            .padding(.horizontal, PikkoSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isAutoQualitySelected: Bool {
        viewModel.viewState.userSelectedQuality == "auto"
            && (viewModel.viewState.effectivePlaybackQuality == nil
                || viewModel.viewState.effectivePlaybackQuality == "auto")
    }

    private func isQualitySelected(_ quality: String) -> Bool {
        if viewModel.viewState.userSelectedQuality == "auto" {
            return viewModel.viewState.effectivePlaybackQuality == quality
        }
        return viewModel.viewState.userSelectedQuality == quality
    }

    private var isPlaying: Bool {
        if case .playing = viewModel.viewState.playbackState {
            return true
        }
        return false
    }

    private var durationText: String {
        guard let duration = viewModel.viewState.duration else {
            return "--:--"
        }
        return VideoDurationFormatter.string(from: duration)
    }
}

struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var videoId: String?
    var context: VideoPlaybackContext = .detail
    var isPictureInPictureEnabled = false

    func makeUIView(context: Context) -> UIView {
        let view = PlayerContainerView()
        guard let playerLayer = view.safePlayerLayer else {
            Logger(category: "VideoPlayer").error("[CrashGuard] recoveredInvalidState area=PlayerContainerView reason=missingAVPlayerLayer videoId=\(videoId ?? "nil") context=\(self.context.rawValue)")
            return view
        }
        playerLayer.player = player
        playerLayer.videoGravity = videoGravity
        view.videoId = videoId
        view.context = self.context
        view.selectedGravity = videoGravity
        if self.context == .shorts {
            Logger(category: "ShortsLayout").debug("[ShortsLayout] aspectMode=fit reason=preserveOriginalRatio")
            Logger(category: "ShortsLayout").debug("[ShortsLayout] videoGravity=\(videoGravity.rawValue)")
            Logger(category: "ShortsLayout").debug("[ShortsLayout] background=blurredThumbnail enabled=false")
        }
        PictureInPictureManager.shared.setup(
            playerLayer: playerLayer,
            videoId: videoId,
            context: self.context,
            isEnabled: isPictureInPictureEnabled
        )
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let uiView = uiView as? PlayerContainerView else { return }
        guard let playerLayer = uiView.safePlayerLayer else {
            Logger(category: "VideoPlayer").error("[CrashGuard] recoveredInvalidState area=PlayerContainerView reason=missingAVPlayerLayer videoId=\(videoId ?? "nil") context=\(self.context.rawValue)")
            return
        }
        playerLayer.player = player
        playerLayer.videoGravity = videoGravity
        uiView.videoId = videoId
        uiView.context = self.context
        uiView.selectedGravity = videoGravity
        if self.context == .shorts {
            Logger(category: "ShortsLayout").debug("[ShortsLayout] aspectMode=fit reason=preserveOriginalRatio")
            Logger(category: "ShortsLayout").debug("[ShortsLayout] aspectMode=fill skipped reason=defaultPreserveOriginal")
        }
        PictureInPictureManager.shared.setup(
            playerLayer: playerLayer,
            videoId: videoId,
            context: self.context,
            isEnabled: isPictureInPictureEnabled
        )
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        guard let uiView = uiView as? PlayerContainerView else { return }
        guard let playerLayer = uiView.safePlayerLayer else { return }
        PictureInPictureManager.shared.detach(playerLayer: playerLayer)
        playerLayer.player = nil
    }
}

private final class PlayerContainerView: UIView {
    private let logger = Logger(category: "ShortsLayout")
    var videoId: String?
    var context: VideoPlaybackContext = .detail
    var selectedGravity: AVLayerVideoGravity = .resizeAspect

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var safePlayerLayer: AVPlayerLayer? {
        guard let playerLayer = layer as? AVPlayerLayer else {
            Logger(category: "VideoPlayer").error("[CrashGuard] forceUnwrapRemoved area=PlayerContainerView.playerLayer")
            return nil
        }
        return playerLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let playerLayer = safePlayerLayer else { return }
        playerLayer.frame = bounds
        guard context == .shorts else { return }
        let presentationSize = playerLayer.player?.currentItem?.presentationSize ?? .zero
        if presentationSize.width <= 0 || presentationSize.height <= 0 {
            logger.debug("[ShortsLayout] presentationSize unknown fallback=aspectFit")
        }
        let contentFrame = ShortsVideoAspectPolicy.aspectFitFrame(contentSize: presentationSize, containerSize: bounds.size)
        logger.debug("[ShortsLayout] containerSize=\(Int(bounds.width))x\(Int(bounds.height)) presentationSize=\(Int(presentationSize.width))x\(Int(presentationSize.height)) contentFrame=\(Int(contentFrame.origin.x)),\(Int(contentFrame.origin.y)),\(Int(contentFrame.width))x\(Int(contentFrame.height)) selectedGravity=\(selectedGravity.rawValue)")
    }
}

@MainActor
final class PictureInPictureManager: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = PictureInPictureManager()

    private let logger = Logger(category: "PiP")
    private weak var playerLayer: AVPlayerLayer?
    private var controller: AVPictureInPictureController?
    private var videoId: String?
    private var context: VideoPlaybackContext?
    private var sessionId: String?

    func setup(
        playerLayer: AVPlayerLayer?,
        videoId: String?,
        context: VideoPlaybackContext,
        isEnabled: Bool
    ) {
        let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        logger.debug("[PiP] support available=\(isSupported)")
        let requestedSessionId = videoId.flatMap { VideoPlaybackCoordinator.shared.currentPlaybackSession(videoId: $0, context: context)?.sessionId }
        logger.debug("[PiP] setup requested videoId=\(videoId ?? "nil") context=\(context.rawValue) sessionId=\(requestedSessionId ?? "nil")")

        guard isEnabled else {
            if self.playerLayer === playerLayer {
                detach(playerLayer: playerLayer)
            }
            return
        }

        guard isSupported else {
            logger.debug("[PiP] setup skipped reason=unsupported")
            return
        }

        guard let playerLayer else {
            logger.debug("[PiP] setup skipped reason=noPlayerLayer")
            return
        }

        if self.playerLayer === playerLayer,
           self.videoId == videoId,
           self.context == context,
           self.sessionId == requestedSessionId,
           controller != nil {
            logger.debug("[PiP] setup skipped reason=alreadyConfigured videoId=\(videoId ?? "nil") sessionId=\(requestedSessionId ?? "nil")")
            return
        }

        if self.videoId == videoId,
           self.context == .shorts,
           context == .detail {
            logger.debug("[PiP] ownership transfer from=shorts to=detail videoId=\(videoId ?? "nil")")
        }

        self.playerLayer = playerLayer
        self.videoId = videoId
        self.context = context
        self.sessionId = requestedSessionId

        controller?.delegate = nil
        guard let pipController = AVPictureInPictureController(playerLayer: playerLayer) else {
            logger.debug("[PiP] setup skipped reason=unsupported")
            return
        }
        pipController.delegate = self
        pipController.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pipController
        logger.debug("[PiP] setup videoId=\(videoId ?? "nil") context=\(context.rawValue) sessionId=\(requestedSessionId ?? "nil") playerLayerExists=true")
    }

    func detach(playerLayer: AVPlayerLayer?) {
        guard self.playerLayer === playerLayer else { return }
        if let videoId,
           context == .shorts,
           VideoPlaybackCoordinator.shared.currentContext == .detail,
           VideoPlaybackCoordinator.shared.currentVideoId == videoId {
            logger.debug("[PiP] teardown skipped reason=ownershipMovedToDetail videoId=\(videoId)")
            return
        }
        let detachedVideoId = videoId
        if controller?.isPictureInPictureActive == true {
            controller?.stopPictureInPicture()
        }
        controller?.delegate = nil
        controller = nil
        self.playerLayer = nil
        videoId = nil
        context = nil
        sessionId = nil
        logger.debug("[PiP] teardown reason=featureExit videoId=\(detachedVideoId ?? "nil")")
    }

    func start(reason: String) {
        logger.debug("[PiP] start requested reason=\(reason) videoId=\(videoId ?? "nil")")
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.debug("[PiP] setup skipped reason=unsupported")
            return
        }
        guard playerLayer != nil else {
            logger.debug("[PiP] setup skipped reason=noPlayerLayer")
            return
        }
        guard let controller else {
            logger.debug("[PiP] setup skipped reason=noPlayerLayer")
            return
        }
        guard !controller.isPictureInPictureActive else { return }
        guard controller.isPictureInPicturePossible else {
            logger.debug("[PiP] setup skipped reason=unsupported")
            return
        }
        controller.startPictureInPicture()
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            logger.debug("[PiP] didStart videoId=\(videoId ?? "nil")")
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            logger.warning("[PiP] failedToStart error=\(error.localizedDescription)")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            logger.debug("[PiP] didStop videoId=\(videoId ?? "nil")")
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            logger.debug("[PiP] restoreUI requested videoId=\(videoId ?? "nil")")
        }
    }
}
