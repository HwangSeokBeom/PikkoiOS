import SwiftUI

struct CommunityDetailView: View {
    @ObservedObject var presenter: CommunityDetailPresenter
    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    @State private var showsPostDeletionAlert = false

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
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        heroCard

                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                        }

                        if let postCard = presenter.viewState.postCard {
                            SectionHeader(
                                title: "게시글",
                                subtitle: "postID \(presenter.viewState.postID)"
                            )

                            CommunityCard(
                                model: postCard,
                                loader: imageLoader,
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
                            }
                        )
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.top, PikkoSpacing.xl)
                    .padding(.bottom, PikkoSpacing.xxl)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
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
            makeStoreDetailView: { _ in AnyView(EmptyView()) }
        )
    }
}

private actor PreviewTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}
