import AVFoundation
import SwiftUI

struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @Environment(\.dismiss) private var dismiss

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
            qualityBottomSheet
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: viewModel.viewState.isQualityMenuPresented)
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
    }

    private var playerSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .fill(.black)

            if let player = viewModel.player {
                VideoPlayerLayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            }

            overlayContent
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
                .foregroundStyle(viewModel.viewState.video.isLiked ? PikkoColor.coralHeart : PikkoColor.accentStrong)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(PikkoColor.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                        .stroke(PikkoColor.line.opacity(0.7), lineWidth: 1)
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

                if !stream.subtitles.isEmpty {
                    Text(stream.subtitles.map(\.name).joined(separator: " · "))
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineLimit(2)
                }
            }
        }
    }

    private func retryOverlay(buttonTitle: String) -> some View {
        VStack(spacing: PikkoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(PikkoColor.warmYellow)

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
                    .background(PikkoColor.accent)
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
                .background(isSelected ? PikkoColor.accent : PikkoColor.surfaceMuted)
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

private struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
