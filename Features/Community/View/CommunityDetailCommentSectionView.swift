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
    let onAuthorChatTapped: (String) -> Void

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

                            if comment.isPending {
                                Text("전송 중")
                                    .font(PikkoTypography.micro)
                                    .foregroundStyle(PikkoColor.secondaryText)
                            } else if comment.isFailed {
                                Text("전송 실패")
                                    .font(PikkoTypography.micro)
                                    .foregroundStyle(PikkoColor.danger)
                            }
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

                        if !comment.isHidden && !comment.isPending && !comment.isFailed && state.editingCommentID != comment.id {
                            HStack(spacing: PikkoSpacing.sm) {
                                if comment.isMine {
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

                                if comment.canChatWithAuthor {
                                    Button("채팅") {
                                        onAuthorChatTapped(comment.authorID)
                                    }
                                    .font(PikkoTypography.captionStrong)
                                    .foregroundStyle(PikkoColor.accentStrong)
                                }
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
            .background(commentBackground(for: comment))
            .overlay {
                if state.highlightedCommentID == comment.id {
                    RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                        .stroke(PikkoColor.accentStrong, lineWidth: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            .id(CommunityCommentAnchor.id(comment.id))
            .onAppear {
                onLoadMoreIfNeeded(comment.id)
            }
        )
    }

    private func commentBackground(for comment: CommunityDetailCommentRowViewState) -> Color {
        if state.highlightedCommentID == comment.id {
            return PikkoColor.accent.opacity(0.16)
        }
        return comment.depth == 0 ? PikkoColor.surfaceElevated : PikkoColor.surfaceMuted
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

enum CommunityCommentAnchor: Hashable {
    case id(String)
}

struct CommunityDetailCommentComposerBar: View {
    let text: String
    let isSubmitting: Bool
    let requiresAuthentication: Bool
    let onTextChanged: (String) -> Void
    let onSubmitTapped: () -> Void
    let onAuthTapped: () -> Void

    var body: some View {
        let canSubmit = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting

        HStack(alignment: .bottom, spacing: PikkoSpacing.sm) {
            TextField(
                requiresAuthentication ? "로그인 후 댓글을 작성할 수 있어요" : "댓글을 입력해 주세요",
                text: Binding(
                    get: { text },
                    set: { newValue in
                        onTextChanged(newValue)
                    }
                ),
                axis: .vertical
            )
            .font(PikkoTypography.body)
            .foregroundStyle(PikkoColor.primaryText)
            .tint(PikkoColor.accentStrong)
            .lineLimit(1...3)
            .padding(.horizontal, PikkoSpacing.md)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(requiresAuthentication ? PikkoColor.gray100 : PikkoColor.surfaceMuted)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PikkoColor.line, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .disabled(requiresAuthentication || isSubmitting)

            if requiresAuthentication {
                Button("로그인") {
                    onAuthTapped()
                }
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.accentStrong)
                .frame(width: 64, height: 44)
                .background(PikkoColor.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(PikkoColor.accent.opacity(0.35), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                Button {
                    onSubmitTapped()
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("등록")
                                .font(PikkoTypography.bodyStrong)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 44)
                    .background(canSubmit ? PikkoColor.accent : PikkoColor.gray300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal, PikkoSpacing.xl)
        .padding(.top, PikkoSpacing.sm)
        .padding(.bottom, PikkoSpacing.sm)
        .background {
            PikkoColor.surface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(PikkoColor.line)
                        .frame(height: 1)
                }
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: -2)
        }
    }
}
