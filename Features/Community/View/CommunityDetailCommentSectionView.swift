import SwiftUI

struct CommunityDetailCommentSectionView: View {
    let state: CommunityDetailCommentSectionState
    let imageLoader: any AuthorizedImageLoading
    let onRetryTapped: () -> Void
    let onAuthTapped: () -> Void
    let onLoadMoreIfNeeded: (String) -> Void
    let onEditTapped: (String) -> Void
    let onEditDraftChanged: (String) -> Void
    let onEditSaveTapped: () -> Void
    let onEditCancelTapped: () -> Void
    let onDeleteConfirmed: (String) -> Void

    @State private var pendingDeletionComment: CommunityDetailCommentRowViewState?

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
            SectionHeader(
                title: "댓글",
                subtitle: state.countText
            )

            if let errorMessage = state.errorMessage,
               !state.comments.isEmpty {
                VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                    ToastView(message: errorMessage, tone: .warning)

                    if state.requiresAuthentication {
                        SecondaryButton(
                            title: "로그인하러 가기",
                            action: onAuthTapped
                        )
                    }
                }
            }

            if state.isInitialLoading && state.comments.isEmpty {
                LoadingView(message: "댓글을 불러오고 있어요")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PikkoSpacing.lg)
            } else if let emptyState = state.emptyState,
                      state.comments.isEmpty {
                EmptyStateView(
                    title: emptyState.title,
                    message: emptyState.message,
                    actionTitle: emptyState.actionTitle,
                    action: {
                        if emptyState.requiresAuthentication {
                            onAuthTapped()
                        } else {
                            onRetryTapped()
                        }
                    }
                )
            } else {
                VStack(alignment: .leading, spacing: PikkoSpacing.md) {
                    ForEach(state.comments) { comment in
                        commentRow(comment)
                    }

                    if state.isLoadingMore {
                        HStack(spacing: PikkoSpacing.sm) {
                            ProgressView()
                            Text("댓글을 더 불러오고 있어요")
                                .font(PikkoTypography.caption)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PikkoSpacing.sm)
                    }
                }
            }
        }
        .alert(item: $pendingDeletionComment) { comment in
            Alert(
                title: Text("댓글을 삭제할까요?"),
                message: Text("삭제한 댓글은 되돌릴 수 없어요."),
                primaryButton: .destructive(Text("삭제")) {
                    onDeleteConfirmed(comment.id)
                },
                secondaryButton: .cancel(Text("취소"))
            )
        }
    }

    private func commentRow(_ comment: CommunityDetailCommentRowViewState) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                HStack(alignment: .top, spacing: PikkoSpacing.sm) {
                    avatar(path: comment.authorAvatarPath)

                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        HStack(spacing: PikkoSpacing.xs) {
                            Text(comment.authorName)
                                .font(PikkoTypography.captionStrong)
                                .foregroundStyle(PikkoColor.primaryText)

                            Text(comment.timeText)
                                .font(PikkoTypography.caption)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }

                        if state.editingCommentID == comment.id {
                            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                                TextEditor(
                                    text: Binding(
                                        get: { state.editingDraftText },
                                        set: { newValue in
                                            onEditDraftChanged(newValue)
                                        }
                                    )
                                )
                                .font(PikkoTypography.body)
                                .frame(minHeight: 88)
                                .padding(PikkoSpacing.sm)
                                .background(PikkoColor.surfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))

                                HStack(spacing: PikkoSpacing.sm) {
                                    SecondaryButton(
                                        title: "취소",
                                        action: onEditCancelTapped
                                    )

                                    PrimaryButton(
                                        title: "저장",
                                        isLoading: state.isSubmittingComment,
                                        action: onEditSaveTapped
                                    )
                                }
                            }
                        } else {
                            Text(comment.content)
                                .font(PikkoTypography.body)
                                .foregroundStyle(comment.isHidden ? PikkoColor.secondaryText : PikkoColor.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if comment.isMine && !comment.isHidden && state.editingCommentID != comment.id {
                            HStack(spacing: PikkoSpacing.sm) {
                                Button("수정") {
                                    onEditTapped(comment.id)
                                }
                                .font(PikkoTypography.captionStrong)
                                .foregroundStyle(PikkoColor.accentStrong)

                                Button("삭제") {
                                    pendingDeletionComment = comment
                                }
                                .font(PikkoTypography.captionStrong)
                                .foregroundStyle(PikkoColor.danger)
                            }
                        }
                    }
                }

                if !comment.replies.isEmpty {
                    VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                        ForEach(comment.replies) { reply in
                            commentRow(reply)
                        }
                    }
                }
            }
            .padding(.leading, CGFloat(comment.depth) * PikkoSpacing.lg)
            .padding(PikkoSpacing.md)
            .background(comment.depth == 0 ? PikkoColor.surfaceElevated : PikkoColor.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            .onAppear {
                onLoadMoreIfNeeded(comment.id)
            }
        )
    }

    private func avatar(path: String?) -> some View {
        AuthorizedAsyncImage(
            path: path,
            loader: imageLoader,
            contentMode: .fill,
            cornerRadius: 16,
            showsProgress: false
        )
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

struct CommunityDetailCommentComposerBar: View {
    let text: String
    let isSubmitting: Bool
    let requiresAuthentication: Bool
    let onTextChanged: (String) -> Void
    let onSubmitTapped: () -> Void
    let onAuthTapped: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: PikkoSpacing.sm) {
            TextField(
                requiresAuthentication ? "로그인 후 댓글을 작성할 수 있어요" : "댓글을 남겨보세요",
                text: Binding(
                    get: { text },
                    set: { newValue in
                        onTextChanged(newValue)
                    }
                ),
                axis: .vertical
            )
            .font(PikkoTypography.body)
            .padding(.horizontal, PikkoSpacing.md)
            .padding(.vertical, PikkoSpacing.sm)
            .background(PikkoColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.floatingCTA, style: .continuous))
            .disabled(requiresAuthentication || isSubmitting)

            if requiresAuthentication {
                SecondaryButton(
                    title: "로그인",
                    action: onAuthTapped
                )
                .frame(width: 92)
            } else {
                PrimaryButton(
                    title: "등록",
                    isLoading: isSubmitting,
                    size: .compact,
                    action: onSubmitTapped
                )
                .frame(width: 92)
            }
        }
        .padding(.horizontal, PikkoSpacing.xl)
        .padding(.top, PikkoSpacing.sm)
        .padding(.bottom, PikkoSpacing.md)
        .background(.ultraThinMaterial)
    }
}
