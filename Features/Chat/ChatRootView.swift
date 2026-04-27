import SwiftUI

struct ChatRootView: View {
    @StateObject private var presenter: ChatPresenter
    private let imageLoader: any AuthorizedImageLoading
    @FocusState private var isComposerFocused: Bool

    init(
        presenter: ChatPresenter,
        imageLoader: any AuthorizedImageLoading
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        self.imageLoader = imageLoader
    }

    var body: some View {
        Group {
            if presenter.viewState.mode == .roomDetail {
                roomDetailView
            } else if presenter.viewState.isLoading {
                loadingView
            } else if presenter.viewState.showsEmptyState {
                emptyView
            } else {
                roomListView
            }
        }
        .background(PikkoColor.background.ignoresSafeArea())
        .pikkoScreen(title: presenter.viewState.title)
        .toolbar {
            if presenter.viewState.showsInternalBackButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await presenter.send(.backToRoomsTapped) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        .task {
            await presenter.send(.onAppear)
        }
    }

    private var loadingView: some View {
        ZStack {
            PikkoColor.background.ignoresSafeArea()
            LoadingView(message: "채팅을 불러오고 있어요")
                .padding(PikkoSpacing.xl)
        }
    }

    private var emptyView: some View {
        ZStack {
            PikkoColor.background.ignoresSafeArea()

            EmptyStateView(
                title: presenter.viewState.emptyTitle ?? "채팅을 불러오지 못했어요",
                message: presenter.viewState.emptyMessage ?? "잠시 후 다시 시도해 주세요.",
                systemImage: "bubble.left.and.bubble.right",
                actionTitle: presenter.viewState.primaryActionTitle,
                action: {
                    Task { await presenter.send(.primaryButtonTapped) }
                }
            )
            .padding(PikkoSpacing.xl)
        }
    }

    private var roomListView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: PikkoSpacing.sm) {
                if let errorMessage = presenter.viewState.errorMessage {
                    ToastView(message: errorMessage, tone: .warning)
                        .padding(.bottom, PikkoSpacing.sm)
                }

                ForEach(presenter.viewState.rooms) { room in
                    Button {
                        Task { await presenter.send(.roomTapped(room.id)) }
                    } label: {
                        ChatRoomRow(room: room, imageLoader: imageLoader)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PikkoSpacing.xl)
            .padding(.top, PikkoSpacing.lg)
            .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset)
        }
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    private var roomDetailView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: PikkoSpacing.sm) {
                    if let errorMessage = presenter.viewState.errorMessage {
                        ToastView(message: errorMessage, tone: .warning)
                            .padding(.bottom, PikkoSpacing.sm)
                    }

                    if presenter.viewState.isLoading && presenter.viewState.messages.isEmpty {
                        LoadingView(message: "메시지를 불러오고 있어요")
                            .frame(maxWidth: .infinity)
                            .padding(.top, PikkoSpacing.xxl)
                    } else if presenter.viewState.showsDetailEmptyState {
                        EmptyStateView(
                            title: presenter.viewState.emptyTitle ?? "아직 대화가 없어요",
                            message: presenter.viewState.emptyMessage ?? "첫 메시지를 보내보세요.",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                        .padding(.top, PikkoSpacing.xxl)
                    } else {
                        ForEach(presenter.viewState.messages) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, PikkoSpacing.xl)
                .padding(.top, PikkoSpacing.lg)
                .padding(.bottom, PikkoSpacing.md)
            }
            .onChange(of: presenter.viewState.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            messageComposer
        }
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    private var messageComposer: some View {
        HStack(alignment: .bottom, spacing: PikkoSpacing.sm) {
            TextField(
                "메시지 입력",
                text: messageTextBinding,
                prompt: Text("메시지 입력")
                    .foregroundStyle(PikkoColor.gray500),
                axis: .vertical
            )
            .lineLimit(1...4)
            .font(PikkoTypography.body)
            .foregroundStyle(PikkoColor.primaryText)
            .tint(PikkoColor.accentStrong)
            .padding(.horizontal, PikkoSpacing.md)
            .padding(.vertical, PikkoSpacing.sm + 2)
            .frame(minHeight: 48)
            .background(PikkoColor.surface)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(PikkoColor.line.opacity(0.8), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            .focused($isComposerFocused)

            Button {
                Task { await presenter.send(.sendMessageTapped) }
            } label: {
                Image(systemName: presenter.viewState.isSending ? "hourglass" : "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(presenter.viewState.canSend ? PikkoColor.accent : PikkoColor.gray400)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!presenter.viewState.canSend)
        }
        .padding(.horizontal, PikkoSpacing.lg)
        .padding(.top, PikkoSpacing.sm)
        .padding(.bottom, PikkoSpacing.sm)
        .background(PikkoColor.background.opacity(0.96))
    }

    private var messageTextBinding: Binding<String> {
        Binding(
            get: { presenter.viewState.messageText },
            set: { value in
                Task { await presenter.send(.messageTextChanged(value)) }
            }
        )
    }
}

private struct ChatRoomRow: View {
    let room: ChatRoomRowViewState
    let imageLoader: any AuthorizedImageLoading

    var body: some View {
        HStack(spacing: PikkoSpacing.md) {
            AuthorizedAsyncImage(
                path: room.avatarPath,
                loader: imageLoader,
                cornerRadius: 24,
                showsProgress: false
            )
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(room.title)
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: PikkoSpacing.sm)

                    Text(room.timeText)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.tertiaryText)
                        .lineLimit(1)
                }

                Text(room.subtitle)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(PikkoSpacing.md)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessageRowViewState

    var body: some View {
        HStack(alignment: .bottom, spacing: PikkoSpacing.xs) {
            if message.isMine {
                Spacer(minLength: 48)
                timestamp
                bubble
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.senderName)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                    bubble
                }
                timestamp
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
    }

    private var bubble: some View {
        Text(message.content)
            .font(PikkoTypography.body)
            .foregroundStyle(message.isMine ? .white : PikkoColor.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PikkoSpacing.md)
            .padding(.vertical, PikkoSpacing.sm)
            .background(message.isMine ? PikkoColor.accent : PikkoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            .frame(maxWidth: 260, alignment: message.isMine ? .trailing : .leading)
    }

    private var timestamp: some View {
        Text(message.timeText)
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.tertiaryText)
            .lineLimit(1)
    }
}
