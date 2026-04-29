import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatRootView: View {
    @StateObject private var presenter: ChatPresenter
    private let imageLoader: any AuthorizedImageLoading
    @FocusState private var isComposerFocused: Bool
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isFileImporterPresented = false

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
        .navigationBarBackButtonHidden(presenter.viewState.showsInternalBackButton)
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
        .onDisappear {
            Task { await presenter.send(.onDisappear) }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleFileImport(result) }
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
                            ChatMessageBubble(message: message, imageLoader: imageLoader)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, PikkoSpacing.xl)
                .padding(.top, PikkoSpacing.lg)
                .padding(.bottom, PikkoSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: presenter.viewState.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.viewState.selectedRoomID != nil {
                messageComposer
            }
        }
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    private var messageComposer: some View {
        let isUploadingFiles = presenter.viewState.isUploadingFiles
        return HStack(alignment: .bottom, spacing: PikkoSpacing.sm) {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 5,
                matching: .images,
                preferredItemEncoding: .automatic
            ) {
                Image(systemName: isUploadingFiles ? "hourglass" : "paperclip")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PikkoColor.accentStrong)
                    .frame(width: 44, height: 44)
                    .background(PikkoColor.surface)
                    .clipShape(Circle())
            }
            .disabled(presenter.viewState.selectedRoomID == nil || isUploadingFiles || presenter.viewState.isSending)

            Button {
                isFileImporterPresented = true
            } label: {
                Image(systemName: isUploadingFiles ? "hourglass" : "doc.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PikkoColor.accentStrong)
                    .frame(width: 44, height: 44)
                    .background(PikkoColor.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(presenter.viewState.selectedRoomID == nil || isUploadingFiles || presenter.viewState.isSending)

            TextField(
                "메시지 입력",
                text: messageTextBinding,
                prompt: Text("메시지 입력")
                    .foregroundStyle(PikkoColor.gray500),
                axis: .vertical
            )
            .lineLimit(1...3)
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
        .overlay(alignment: .topLeading) {
            if !presenter.viewState.attachedFilePaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PikkoSpacing.xs) {
                        ForEach(presenter.viewState.attachedFilePaths, id: \.self) { path in
                            ChatAttachmentToken(path: path) {
                                Task { await presenter.send(.attachedFileRemoved(path)) }
                            }
                        }
                    }
                    .padding(.horizontal, PikkoSpacing.lg)
                    .padding(.bottom, PikkoSpacing.xs)
                    .offset(y: -40)
                }
            }
        }
        .padding(.horizontal, PikkoSpacing.lg)
        .padding(.top, PikkoSpacing.sm)
        .padding(.bottom, PikkoSpacing.sm + (isComposerFocused ? 0 : RootTabBarMetrics.contentHeight))
        .background(PikkoColor.background.opacity(0.96))
        .onAppear {
            Logger.shared.debug(
                "[ChatInput] inputContainerAdded=true inputBottomConstraintTarget=\(isComposerFocused ? "keyboardLayoutGuide" : "tabBarTop") isHidden=false"
            )
        }
        .onChange(of: isComposerFocused) { _, focused in
            Logger.shared.debug(
                "[ChatInput] inputContainerAdded=true inputBottomConstraintTarget=\(focused ? "keyboardLayoutGuide" : "tabBarTop") isHidden=false"
            )
        }
        .onChange(of: selectedPhotoItems) { _, items in
            Task { await handleImageSelection(items) }
        }
    }

    private var messageTextBinding: Binding<String> {
        Binding(
            get: { presenter.viewState.messageText },
            set: { value in
                Task { await presenter.send(.messageTextChanged(value)) }
            }
        )
    }

    private func handleImageSelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var files: [ChatUploadFile] = []
        for (index, item) in items.enumerated() {
            guard let rawData = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let jpegData = image.jpegData(compressionQuality: 0.88),
                  !jpegData.isEmpty else {
                continue
            }

            files.append(
                ChatUploadFile(
                    data: jpegData,
                    fileName: "chat-\(Int(Date().timeIntervalSince1970))-\(index).jpg",
                    mimeType: "image/jpeg"
                )
            )
        }

        selectedPhotoItems = []
        await presenter.send(.filesSelected(files))
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let files = urls.prefix(5).compactMap { url -> ChatUploadFile? in
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                return nil
            }
            return ChatUploadFile(
                data: data,
                fileName: url.lastPathComponent,
                mimeType: "application/pdf"
            )
        }
        await presenter.send(.filesSelected(files))
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
    let imageLoader: any AuthorizedImageLoading

    var body: some View {
        VStack(spacing: PikkoSpacing.xs) {
            if let dateText = message.dateText {
                Text(dateText)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .padding(.horizontal, PikkoSpacing.md)
                    .padding(.vertical, 6)
                    .background(PikkoColor.surface)
                    .clipShape(Capsule())
                    .padding(.vertical, PikkoSpacing.sm)
            }

            HStack(alignment: .bottom, spacing: PikkoSpacing.xs) {
                if message.isMine {
                    Spacer(minLength: 48)
                    timestampAndStatus
                    bubble
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.senderName)
                            .font(PikkoTypography.caption)
                            .foregroundStyle(PikkoColor.secondaryText)
                        bubble
                    }
                    timestampAndStatus
                    Spacer(minLength: 48)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            if !message.content.isEmpty {
                Text(message.content)
                    .font(PikkoTypography.body)
                    .foregroundStyle(message.isMine ? .white : PikkoColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !message.filePaths.isEmpty {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(82), spacing: 6), count: min(message.filePaths.count, 2)),
                    spacing: 6
                ) {
                    ForEach(message.filePaths, id: \.self) { path in
                        if isImagePath(path) {
                            AuthorizedAsyncImage(
                                path: path,
                                loader: imageLoader,
                                contentMode: .fill,
                                cornerRadius: PikkoRadius.card,
                                showsProgress: true
                            )
                            .frame(width: 82, height: 82)
                            .clipped()
                        } else {
                            Link(destination: URL(string: path) ?? URL(fileURLWithPath: path)) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.fill")
                                    Text((path as NSString).lastPathComponent)
                                        .lineLimit(1)
                                }
                                .font(PikkoTypography.caption)
                                .foregroundStyle(message.isMine ? .white : PikkoColor.accentStrong)
                                .frame(width: 164, height: 40, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, PikkoSpacing.md)
        .padding(.vertical, PikkoSpacing.sm)
        .background(message.isMine ? bubbleColor : PikkoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .frame(maxWidth: 260, alignment: message.isMine ? .trailing : .leading)
    }

    private var timestampAndStatus: some View {
        VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
            Text(message.timeText)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.tertiaryText)
                .lineLimit(1)

            if let statusText = message.statusText {
                Text(statusText)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(message.sendStatus == .failed ? Color.red : PikkoColor.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private var bubbleColor: Color {
        message.sendStatus == .failed ? Color.red.opacity(0.72) : PikkoColor.accent
    }

    private func isImagePath(_ path: String) -> Bool {
        let value = path.lowercased()
        return value.hasSuffix(".jpg")
            || value.hasSuffix(".jpeg")
            || value.hasSuffix(".png")
            || value.hasSuffix(".gif")
    }
}

private struct ChatAttachmentToken: View {
    let path: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: PikkoSpacing.xs) {
            Text((path as NSString).lastPathComponent)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(PikkoColor.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PikkoSpacing.sm)
        .frame(height: 32)
        .background(PikkoColor.surfaceElevated)
        .clipShape(Capsule())
    }
}
