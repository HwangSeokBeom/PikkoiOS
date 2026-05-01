import SwiftUI

struct VideoListView: View {
    private enum ScrollAnchor {
        static let top = "video-scroll-top"
    }

    @ObservedObject var presenter: VideoListPresenter
    let imageLoader: any AuthorizedImageLoading
    let resetTrigger: Int

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
        .pikkoScreen(title: "영상")
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: PikkoSpacing.md) {
                    Color.clear
                        .frame(height: 0)
                        .id(ScrollAnchor.top)

                    header

                    if let errorMessage = presenter.viewState.errorMessage {
                        ToastView(message: errorMessage, tone: .warning)
                    }

                    ForEach(presenter.viewState.videos) { video in
                        VideoCardView(
                            model: video,
                            imageLoader: imageLoader,
                            onTap: {
                                Task { await presenter.send(.videoTapped(video.id)) }
                            },
                            onLikeTap: {
                                Task { await presenter.send(.videoLikeTapped(video.id)) }
                            }
                        )
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
                .padding(.horizontal, PikkoSpacing.lg)
                .padding(.top, PikkoSpacing.md)
                .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset)
            }
            .onChange(of: resetTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(ScrollAnchor.top, anchor: .top)
                }
                Task { await presenter.send(.refreshRequested) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            Text("영상")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(PikkoColor.primaryText)

            Text("픽업 메뉴를 영상으로 미리 확인해보세요.")
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .padding(.bottom, PikkoSpacing.xs)
    }
}
