import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatRootView: View {
    private enum Layout {
        static let estimatedComposerHeight: CGFloat = 76
        static let composerBottomPadding: CGFloat = PikkoSpacing.sm
        static let messageListBottomGap: CGFloat = PikkoSpacing.lg
        static let inputFrameTolerance: CGFloat = 1
    }

    private enum CoordinateSpaceName {
        static let roomDetailRoot = "ChatRoomDetailRoot"
    }

    @StateObject private var presenter: ChatPresenter
    @StateObject private var keyboardObserver = ChatKeyboardObserver()
    private let imageLoader: any AuthorizedImageLoading
    @FocusState private var isComposerFocused: Bool
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isFileImporterPresented = false
    @State private var hasLoggedComposerInstall = false
    @State private var isDetailEmptyStateVisible = false
    @State private var chatViewInstanceID = UUID().uuidString
    @State private var isRoomDetailVisible = false
    @State private var measuredComposerHeight = Layout.estimatedComposerHeight

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
        let storeInquiryRooms = presenter.viewState.rooms.filter { $0.section == .storeInquiry }
        let generalRooms = presenter.viewState.rooms.filter { $0.section == .general }
        return ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                if let errorMessage = presenter.viewState.errorMessage {
                    ToastView(message: errorMessage, tone: .warning)
                        .padding(.bottom, PikkoSpacing.sm)
                }

                if !storeInquiryRooms.isEmpty {
                    chatListSectionTitle("가게 문의")
                    ForEach(storeInquiryRooms) { room in
                        Button {
                            Task { await presenter.send(.roomTapped(room.id)) }
                        } label: {
                            ChatRoomRow(room: room, imageLoader: imageLoader)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !generalRooms.isEmpty {
                    chatListSectionTitle("일반 채팅")
                        .padding(.top, storeInquiryRooms.isEmpty ? 0 : PikkoSpacing.md)
                    ForEach(generalRooms) { room in
                        Button {
                            Task { await presenter.send(.roomTapped(room.id)) }
                        } label: {
                            ChatRoomRow(room: room, imageLoader: imageLoader)
                        }
                        .buttonStyle(.plain)
                    }
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
        GeometryReader { rootProxy in
            roomDetailContent(containerWidth: rootProxy.size.width)
                .coordinateSpace(name: CoordinateSpaceName.roomDetailRoot)
                .onAppear {
                    isRoomDetailVisible = true
                    Logger.shared.debug("[ChatVC] viewWillAppear id=\(chatViewInstanceID)")
                    Logger.shared.debug("[ChatVC] viewDidAppear id=\(chatViewInstanceID)")
                }
                .onDisappear {
                    isRoomDetailVisible = false
                    isComposerFocused = false
                    Logger.shared.debug("[ChatVC] viewWillDisappear id=\(chatViewInstanceID)")
                    Logger.shared.debug("[ChatInput] observerRemoved=true")
                }
        }
    }

    private func roomDetailContent(containerWidth: CGFloat) -> some View {
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
                        .frame(maxWidth: .infinity)
                        .padding(.top, PikkoSpacing.xxl)
                        .zIndex(0)
                        .onAppear {
                            isDetailEmptyStateVisible = true
                            Logger.shared.debug("[ChatEmptyState] visible=true inputVisible=\(presenter.viewState.selectedRoomID != nil)")
                        }
                        .onDisappear {
                            isDetailEmptyStateVisible = false
                            Logger.shared.debug("[ChatEmptyState] visible=false inputVisible=\(presenter.viewState.selectedRoomID != nil)")
                        }
                    } else {
                        ForEach(presenter.viewState.messages) { message in
                            ChatMessageBubble(message: message, imageLoader: imageLoader)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, PikkoSpacing.xl)
                .padding(.top, PikkoSpacing.lg)
                .padding(.bottom, messageListBottomInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, messageListBottomInset, for: .scrollIndicators)
            .onAppear {
                updateMessageListInsets()
            }
            .onChange(of: measuredComposerHeight) { _, _ in
                updateMessageListInsets()
            }
            .onChange(of: keyboardObserver.keyboardHeight) { _, _ in
                updateMessageListInsets()
            }
            .onChange(of: presenter.viewState.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.viewState.mode == .roomDetail {
                messageComposer(containerWidth: containerWidth)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: keyboardObserver.animationDuration), value: keyboardObserver.keyboardHeight)
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    private var messageListBottomInset: CGFloat {
        measuredComposerHeight
            + Layout.messageListBottomGap
            + composerBottomPadding
    }

    private var composerBottomPadding: CGFloat {
        Layout.composerBottomPadding
            + (keyboardObserver.isKeyboardVisible ? 0 : customTabBarAvoidanceHeight)
    }

    private var customTabBarAvoidanceHeight: CGFloat {
        RootTabBarMetrics.contentHeight + RootTabBarMetrics.floatingCenterOverlap
    }

    private func messageComposer(containerWidth: CGFloat) -> some View {
        let isUploadingFiles = presenter.viewState.isUploadingFiles
        let resolvedContainerWidth = max(containerWidth, 0)
        return VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            if !presenter.viewState.attachedFilePaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PikkoSpacing.xs) {
                        ForEach(presenter.viewState.attachedFilePaths, id: \.self) { path in
                            ChatAttachmentToken(path: path) {
                                Task { await presenter.send(.attachedFileRemoved(path)) }
                            }
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: PikkoSpacing.sm) {
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
                    Task {
                        await presenter.send(.sendMessageTapped)
                        await MainActor.run {
                            isComposerFocused = true
                        }
                    }
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
        }
        .padding(.horizontal, PikkoSpacing.lg)
        .padding(.top, PikkoSpacing.sm)
        .frame(width: resolvedContainerWidth, alignment: .center)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ChatComposerHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .padding(.bottom, composerBottomPadding)
        .transformEffect(.identity)
        .background {
            GeometryReader { proxy in
                PikkoColor.background.opacity(0.96)
                    .onAppear {
                        installInputContainerIfNeeded()
                        logChatInputLayout(
                            proxy: proxy,
                            containerWidth: resolvedContainerWidth,
                            reason: "onAppear",
                            keyboardVisible: keyboardObserver.isKeyboardVisible
                        )
                    }
                    .onChange(of: proxy.frame(in: .named(CoordinateSpaceName.roomDetailRoot))) { _, _ in
                        logChatInputLayout(
                            proxy: proxy,
                            containerWidth: resolvedContainerWidth,
                            reason: "frameChanged",
                            keyboardVisible: keyboardObserver.isKeyboardVisible
                        )
                    }
            }
        }
        .onPreferenceChange(ChatComposerHeightPreferenceKey.self) { height in
            updateMeasuredComposerHeight(height)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isComposerFocused = true
        }
        .onChange(of: isComposerFocused) { _, focused in
            updateInputBottomConstraint(target: keyboardObserver.isKeyboardVisible ? "keyboard" : "tabBarTop")
            Logger.shared.debug("[ChatInput] keyboardVisible=\(focused)")
        }
        .onChange(of: keyboardObserver.keyboardHeight) { _, _ in
            logComposerKeyboardState()
        }
        .onChange(of: keyboardObserver.isKeyboardVisible) { _, _ in
            logComposerKeyboardState()
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

    private func installInputContainerIfNeeded() {
        if hasLoggedComposerInstall {
            Logger.shared.debug("[ChatInput] install skipped if already added")
        } else {
            hasLoggedComposerInstall = true
            Logger.shared.debug("[ChatInput] installInputContainerIfNeeded added=true")
        }
    }

    private func updateInputBottomConstraint(target: String) {
        Logger.shared.debug("[ChatInput] bottomTarget=\(target)")
    }

    private func updateMeasuredComposerHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        guard abs(measuredComposerHeight - height) > Layout.inputFrameTolerance else { return }
        measuredComposerHeight = height
        Logger.shared.debug("[ChatComposer] measuredHeight=\(height)")
    }

    private func logComposerKeyboardState() {
        Logger.shared.debug(
            "[ChatComposer] keyboardHeight=\(keyboardObserver.keyboardHeight) isKeyboardVisible=\(keyboardObserver.isKeyboardVisible)"
        )
        Logger.shared.debug(
            "[ChatComposer] bottomPadding=\(composerBottomPadding) customTabBarHeight=\(keyboardObserver.isKeyboardVisible ? 0 : customTabBarAvoidanceHeight)"
        )
        Logger.shared.debug("[ChatComposer] visible=true")
    }

    private func logChatInputLayout(
        proxy: GeometryProxy,
        containerWidth: CGFloat,
        reason: String,
        keyboardVisible: Bool
    ) {
        guard isRoomDetailVisible else { return }

        let localFrame = proxy.frame(in: .named(CoordinateSpaceName.roomDetailRoot))
        let globalFrame = proxy.frame(in: .global)
        let expectedWidth = containerWidth
        let bottomTarget = keyboardVisible ? "keyboard" : "tabBarTop"
        updateInputBottomConstraint(target: bottomTarget)
        Logger.shared.debug("[ChatInput] inputFrame=\(localFrame.debugDescription)")
        Logger.shared.debug("[ChatInput] globalFrame=\(globalFrame.debugDescription)")
        Logger.shared.debug("[ChatInput] isHidden=false alpha=1 frame=\(localFrame.debugDescription)")
        Logger.shared.debug("[ChatInput] superviewExists=true")
        Logger.shared.debug("[ChatInput] coveredByEmptyState=false")
        Logger.shared.debug("[ChatInput] viewSafeAreaInsets=\(String(describing: proxy.safeAreaInsets))")
        Logger.shared.debug("[ChatInput] tabBarFrame=custom(height:\(RootTabBarMetrics.contentHeight))")
        Logger.shared.debug("[ChatInput] keyboardVisible=\(keyboardVisible)")
        Logger.shared.debug(
            "[ChatComposer] keyboardHeight=\(keyboardObserver.keyboardHeight) isKeyboardVisible=\(keyboardObserver.isKeyboardVisible)"
        )
        Logger.shared.debug(
            "[ChatComposer] bottomPadding=\(composerBottomPadding) customTabBarHeight=\(keyboardObserver.isKeyboardVisible ? 0 : customTabBarAvoidanceHeight)"
        )
        Logger.shared.debug("[ChatComposer] visible=true")

        validateComposerVisibility(globalFrame: globalFrame)

        validateInputHorizontalFrame(
            frame: localFrame,
            expectedWidth: expectedWidth,
            bottomTarget: bottomTarget,
            reason: reason
        )
    }

    private func validateComposerVisibility(globalFrame: CGRect) {
        let screenBounds = UIScreen.main.bounds
        let hasVisibleHeight = globalFrame.height > 0
            && globalFrame.maxY > screenBounds.minY
            && globalFrame.minY < screenBounds.maxY

        if hasVisibleHeight {
            return
        }

        let reason: String
        if globalFrame.height <= 0 {
            reason = "zeroHeight"
        } else if globalFrame.minY >= screenBounds.maxY {
            reason = "belowScreen"
        } else {
            reason = "aboveScreen"
        }

        Logger.shared.error(
            "[ChatComposer] composerNotVisible reason=\(reason) globalFrame=\(globalFrame.debugDescription) screenBounds=\(screenBounds.debugDescription)"
        )
    }

    private func validateInputHorizontalFrame(
        frame: CGRect,
        expectedWidth: CGFloat,
        bottomTarget: String,
        reason: String
    ) {
        guard expectedWidth > 0 else { return }

        let hasInvalidMinX = abs(frame.minX) > Layout.inputFrameTolerance
        let hasInvalidWidth = abs(frame.width - expectedWidth) > Layout.inputFrameTolerance
        guard hasInvalidMinX || hasInvalidWidth else {
            Logger.shared.debug(
                "[ChatInput] layoutValid minX=\(frame.minX) width=\(frame.width) targetWidth=\(expectedWidth) bottomTarget=\(bottomTarget)"
            )
            return
        }

        Logger.shared.error(
            "[ChatInput] invalidHorizontalFrame minX=\(frame.minX) expected=0 width=\(frame.width) expectedWidth=\(expectedWidth) reason=\(reason)"
        )
    }

    private func updateMessageListInsets() {
        Logger.shared.debug(
            "[ChatInput] messageListBottomInset=\(messageListBottomInset) composerMeasuredHeight=\(measuredComposerHeight) keyboardVisible=\(keyboardObserver.isKeyboardVisible)"
        )
    }

    private func chatListSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(PikkoTypography.captionStrong)
            .foregroundStyle(PikkoColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PikkoSpacing.xs)
            .padding(.bottom, PikkoSpacing.xs)
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

private struct ChatComposerHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
private final class ChatKeyboardObserver: ObservableObject {
    @Published private(set) var keyboardHeight: CGFloat = 0
    @Published private(set) var isKeyboardVisible = false
    @Published private(set) var animationDuration: Double = 0.25
    @Published private(set) var animationCurve: UInt = 0

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
        keyboardHeight = keyboardOverlapHeight(from: notification)
        isKeyboardVisible = keyboardHeight > 0
        animationDuration = keyboardAnimationDuration(from: notification)
        animationCurve = keyboardAnimationCurve(from: notification)
        Logger.shared.debug("[ChatKeyboard] willChangeFrame height=\(keyboardHeight)")
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        keyboardHeight = 0
        isKeyboardVisible = false
        animationDuration = keyboardAnimationDuration(from: notification)
        animationCurve = keyboardAnimationCurve(from: notification)
        Logger.shared.debug("[ChatKeyboard] willHide")
    }

    private func keyboardOverlapHeight(from notification: Notification) -> CGFloat {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }

        let windowBounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .bounds ?? UIScreen.main.bounds
        return max(0, windowBounds.maxY - endFrame.minY)
    }

    private func keyboardAnimationDuration(from notification: Notification) -> Double {
        notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    }

    private func keyboardAnimationCurve(from notification: Notification) -> UInt {
        notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
    }
}
