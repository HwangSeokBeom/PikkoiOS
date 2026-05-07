import SwiftUI

struct VideoListView: View {
    private enum ScrollAnchor {
        static let top = "video-scroll-top"
    }

    @ObservedObject var presenter: VideoListPresenter
    let imageLoader: any AuthorizedImageLoading
    let resetTrigger: Int
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
                            onTap: {
                                Task { await presenter.send(.videoTapped(video.id)) }
                            },
                            onLikeTap: {
                                Task { await presenter.send(.videoLikeTapped(video.id)) }
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
                Task { await presenter.send(.videoAppeared(videoID)) }
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
    let onTap: () -> Void
    let onLikeTap: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            AuthorizedAsyncImage(
                path: model.thumbnailURL,
                loader: imageLoader,
                contentMode: .fill,
                cornerRadius: 0,
                showsProgress: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [
                        .black.opacity(0.1),
                        .black.opacity(0.24),
                        .black.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            Button(action: onTap) {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("영상 재생")

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

                        actionButton(systemImage: "text.bubble.fill", title: "댓글", isActive: false, action: onTap)
                        actionButton(systemImage: "square.and.arrow.up", title: "공유", isActive: false, action: {})
                    }
                }
                .padding(.horizontal, PikkoSpacing.lg)
                .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset + PikkoSpacing.xl)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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

    private func metaPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(PikkoTypography.captionStrong)
        }
        .foregroundStyle(.white.opacity(0.84))
    }
}
