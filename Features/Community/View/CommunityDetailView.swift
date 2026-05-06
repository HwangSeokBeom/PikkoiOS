import SwiftUI
import UIKit

struct CommunityDetailView: View {
    @ObservedObject var presenter: CommunityDetailPresenter
    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    @State private var showsPostDeletionAlert = false
    @StateObject private var keyboardObserver = CommunityDetailKeyboardObserver()

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            if presenter.viewState.isLoading && !presenter.viewState.hasLoadedContent {
                LoadingView(message: "게시글 상세를 준비하고 있어요")
                    .padding(PikkoSpacing.xl)
            } else if let emptyState = presenter.viewState.emptyState,
                      !presenter.viewState.hasLoadedContent {
                EmptyStateView(
                    title: emptyState.title,
                    message: emptyState.message,
                    actionTitle: emptyState.actionTitle,
                    action: {
                        if emptyState.requiresAuthentication {
                            onAuthTap()
                        } else {
                            Task { await presenter.send(.retryTapped) }
                        }
                    }
                )
                .padding(PikkoSpacing.xl)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                            heroCard

                            if let errorMessage = presenter.viewState.errorMessage {
                                ToastView(message: errorMessage, tone: .warning)
                            }

                            if let postCard = presenter.viewState.postCard {
                                SectionHeader(
                                    title: "게시글"
                                )

                                CommunityCard(
                                    model: postCard,
                                    loader: imageLoader,
                                    onAuthorChatTapped: { authorID in
                                        Task { await presenter.send(.authorChatTapped(authorID)) }
                                    },
                                    onLikeTapped: {
                                        Task { await presenter.send(.likeTapped) }
                                    },
                                    onStoreSnippetTapped: { storeID in
                                        Task { await presenter.send(.storeSnippetTapped(storeID)) }
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                                .pikkoShadow(PikkoShadow.card)
                            }

                            footerCard

                            CommunityDetailCommentSectionView(
                                state: presenter.viewState.commentSection,
                                imageLoader: imageLoader,
                                onRetryTapped: {
                                    Task { await presenter.send(.commentsRetryTapped) }
                                },
                                onAuthTapped: onAuthTap,
                                onLoadMoreIfNeeded: { commentID in
                                    Task { await presenter.send(.commentLoadMoreIfNeeded(commentID)) }
                                },
                                onEditTapped: { commentID in
                                    Task { await presenter.send(.commentEditTapped(commentID)) }
                                },
                                onEditDraftChanged: { draft in
                                    Task { await presenter.send(.commentEditDraftChanged(draft)) }
                                },
                                onEditSaveTapped: {
                                    Task { await presenter.send(.commentEditSaveTapped) }
                                },
                                onEditCancelTapped: {
                                    Task { await presenter.send(.commentEditCancelled) }
                                },
                                onDeleteConfirmed: { commentID in
                                    Task { await presenter.send(.commentDeleteConfirmed(commentID)) }
                                },
                                onAuthorChatTapped: { authorID in
                                    Task { await presenter.send(.commentAuthorChatTapped(authorID)) }
                                }
                            )
                        }
                        .padding(.horizontal, PikkoSpacing.xl)
                        .padding(.top, PikkoSpacing.xl)
                        .padding(.bottom, PikkoSpacing.xxl + composerReservedBottomInset)
                    }
                    .contentMargins(.bottom, PikkoSpacing.lg, for: .scrollIndicators)
                    .onChange(of: presenter.viewState.commentSection.highlightedCommentID) { _, commentID in
                        guard let commentID else { return }
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(.snappy(duration: 0.28)) {
                                proxy.scrollTo(CommunityCommentAnchor.id(commentID), anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.viewState.hasLoadedContent {
                CommunityDetailCommentComposerBar(
                    text: presenter.viewState.commentSection.composerText,
                    isSubmitting: presenter.viewState.commentSection.isSubmittingComment,
                    requiresAuthentication: presenter.viewState.commentSection.requiresAuthentication,
                    onTextChanged: { text in
                        Task { await presenter.send(.commentComposerChanged(text)) }
                    },
                    onSubmitTapped: {
                        Task { await presenter.send(.commentSubmitTapped) }
                    },
                    onAuthTapped: onAuthTap
                )
                .padding(.bottom, composerBottomAvoidanceInset)
                .background(PikkoColor.background.opacity(0.98))
            }
        }
        .navigationTitle("게시글 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presenter.viewState.canManagePost {
                ToolbarItem(placement: .topBarTrailing) {
                    if presenter.viewState.isDeletingPost {
                        ProgressView()
                    } else {
                        Menu {
                            Button("게시글 수정") {
                                Task { await presenter.send(.postEditTapped) }
                            }

                            Button("게시글 삭제", role: .destructive) {
                                showsPostDeletionAlert = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(PikkoColor.primaryText)
                        }
                    }
                }
            }
        }
        .alert("게시글을 삭제할까요?", isPresented: $showsPostDeletionAlert) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                Task { await presenter.send(.postDeleteConfirmed) }
            }
        } message: {
            Text("삭제한 게시글은 되돌릴 수 없어요.")
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text(presenter.viewState.heroEyebrow)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.accentStrong)

            Text(presenter.viewState.heroTitle)
                .font(PikkoTypography.hero)
                .foregroundStyle(PikkoColor.primaryText)

            Text(presenter.viewState.heroMessage)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text(presenter.viewState.footerTitle)
                .font(PikkoTypography.cardTitle)
                .foregroundStyle(PikkoColor.primaryText)

            Text(presenter.viewState.footerMessage)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private var composerBottomAvoidanceInset: CGFloat {
        keyboardObserver.isKeyboardVisible ? 0 : RootTabBarMetrics.contentHeight
    }

    private var composerReservedBottomInset: CGFloat {
        88 + composerBottomAvoidanceInset
    }
}

@MainActor
private final class CommunityDetailKeyboardObserver: ObservableObject {
    @Published private(set) var isKeyboardVisible = false

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleKeyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            isKeyboardVisible = false
            return
        }

        let windowBounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .bounds ?? UIScreen.main.bounds
        isKeyboardVisible = max(0, windowBounds.maxY - endFrame.minY) > 0
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        isKeyboardVisible = false
    }
}

#Preview {
    NavigationStack {
        PreviewCommunityDetailContainer()
    }
}

@MainActor
private struct PreviewCommunityDetailInteractor: CommunityDetailInteracting {
    func loadInitialContent() async throws -> CommunityDetailContent {
        .fallback(postID: "post-001")
    }

    func deletePost() async throws {}

    func loadComments(nextCursor: String?) async throws -> CursorPage<CommunityComment> {
        CursorPage(items: CommunityDetailContent.fallback(postID: "post-001").detail.comments, nextCursor: nil)
    }

    func createComment(content: String) async throws -> CommunityComment {
        CommunityComment(
            id: "preview-created-comment",
            postID: "post-001",
            parentCommentID: nil,
            author: CommunityPostAuthor(
                id: "preview-me",
                nick: "프리뷰 사용자",
                profileImagePath: nil
            ),
            content: content,
            createdAt: Date(),
            updatedAt: nil,
            isMine: true,
            isHidden: false,
            replies: []
        )
    }

    func updateComment(commentID: String, content: String) async throws -> CommunityComment {
        CommunityComment(
            id: commentID,
            postID: "post-001",
            parentCommentID: nil,
            author: CommunityPostAuthor(
                id: "preview-me",
                nick: "프리뷰 사용자",
                profileImagePath: nil
            ),
            content: content,
            createdAt: Date(),
            updatedAt: Date(),
            isMine: true,
            isHidden: false,
            replies: []
        )
    }

    func deleteComment(commentID: String) async throws {}

    func updateLikeStatus(isLiked: Bool) async throws -> Bool {
        isLiked
    }
}

@MainActor
private struct PreviewCommunityDetailContainer: View {
    var body: some View {
        let router = CommunityDetailRouter()
        CommunityDetailRootView(
            presenter: CommunityDetailPresenter(
                postID: "post-001",
                interactor: PreviewCommunityDetailInteractor(),
                router: router,
                sessionStore: SessionStore(
                    tokenStore: PreviewTokenStore(),
                    userDefaultsStore: UserDefaultsStore(userDefaults: UserDefaults(suiteName: "preview.community.detail")!)
                )
            ),
            router: router,
            imageLoader: PreviewAuthorizedImageLoader(),
            makeAuthView: { _, _ in AnyView(EmptyView()) },
            makeCommunityComposerView: { _, _, _ in AnyView(EmptyView()) },
            makeStoreDetailView: { _ in AnyView(EmptyView()) },
            makeChatView: { _ in AnyView(EmptyView()) }
        )
    }
}

private actor PreviewTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}
