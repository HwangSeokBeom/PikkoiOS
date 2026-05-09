import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatRootView: View {
    private enum Layout {
        static let estimatedComposerHeight: CGFloat = 76
        static let composerBottomPadding: CGFloat = PikkoSpacing.sm
        static let messageListBottomGap: CGFloat = PikkoSpacing.lg
        static let geometryTolerance: CGFloat = 1
        static let nearBottomThreshold: CGFloat = 140
    }

    private enum CoordinateSpaceName {
        static let roomDetailRoot = "ChatRoomDetailRoot"
        static let messages = "ChatMessagesScroll"
    }

    @StateObject private var presenter: ChatPresenter
    @StateObject private var keyboardObserver = ChatKeyboardObserver()
    private let imageLoader: any AuthorizedImageLoading
    @FocusState private var isComposerFocused: Bool
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isFileImporterPresented = false
    @State private var isDetailEmptyStateVisible = false
    @State private var chatViewInstanceID = UUID().uuidString
    @State private var isRoomDetailVisible = false
    @State private var measuredComposerHeight = Layout.estimatedComposerHeight
    private let presentationKind: ChatPresentationKind

    init(
        presenter: ChatPresenter,
        imageLoader: any AuthorizedImageLoading,
        presentationKind: ChatPresentationKind = .internal
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        self.imageLoader = imageLoader
        self.presentationKind = presentationKind
    }

    var body: some View {
        Group {
            if presenter.viewState.mode == .roomDetail {
                roomDetailView
                    .id(presenter.viewState.selectedRoomID ?? "room-detail")
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
            if presenter.viewState.mode == .roomDetail {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await presenter.send(
                                presenter.viewState.isSearchActive ? .searchDismissed : .searchTapped
                            )
                        }
                    } label: {
                        Image(systemName: presenter.viewState.isSearchActive ? "xmark" : "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        .task {
            await presenter.send(.onAppear(instanceID: chatViewInstanceID, presentationKind: presentationKind))
        }
        .onDisappear {
            Task { await presenter.send(.onDisappear(instanceID: chatViewInstanceID, presentationKind: presentationKind)) }
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
                        .onAppear {
                            if generalRooms.isEmpty, room.id == storeInquiryRooms.last?.id {
                                Task { await presenter.send(.roomListReachedEnd) }
                            }
                        }
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
                        .onAppear {
                            if room.id == generalRooms.last?.id {
                                Task { await presenter.send(.roomListReachedEnd) }
                            }
                        }
                    }
                }

                if presenter.viewState.isLoadingNextPage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PikkoSpacing.md)
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
            roomDetailContent(containerSize: rootProxy.size)
                .coordinateSpace(name: CoordinateSpaceName.roomDetailRoot)
                .onAppear {
                    isRoomDetailVisible = true
                    keyboardObserver.activate()
                    Logger.shared.debug("[ChatView] onAppear id=\(chatViewInstanceID)")
#if DEBUG
                    if ChatDebugOptions.isComposerGeometryLoggingEnabled {
                        Logger.shared.debug("[ChatComposer] visible=true")
                    }
#endif
                }
                .onDisappear {
                    isRoomDetailVisible = false
                    isComposerFocused = false
                    keyboardObserver.deactivate()
                    Logger.shared.debug("[ChatView] onDisappear id=\(chatViewInstanceID)")
                    Logger.shared.debug("[ChatKeyboard] observerRemoved=true")
                }
        }
    }

    private func roomDetailContent(containerSize: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: PikkoSpacing.sm) {
                    if let errorMessage = presenter.viewState.errorMessage {
                        ToastView(message: errorMessage, tone: .warning)
                            .padding(.bottom, PikkoSpacing.sm)
                    }

                    if presenter.viewState.isSearchActive {
                        searchPanel
                            .padding(.bottom, PikkoSpacing.xs)
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

                    Color.clear
                        .frame(height: 1)
                        .id(ChatBottomAnchor.id)
                        .background(
                            GeometryReader { bottomProxy in
                                Color.clear.preference(
                                    key: ChatBottomDistancePreferenceKey.self,
                                    value: bottomProxy.frame(in: .named(CoordinateSpaceName.messages)).maxY
                                )
                            }
                        )
                }
                .padding(.horizontal, PikkoSpacing.xl)
                .padding(.top, PikkoSpacing.lg)
                .padding(.bottom, messageListBottomInset)
            }
            .coordinateSpace(name: CoordinateSpaceName.messages)
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
            .onPreferenceChange(ChatBottomDistancePreferenceKey.self) { bottomY in
                updateNearBottomState(bottomY: bottomY, containerHeight: containerSize.height)
            }
            .onChange(of: presenter.viewState.scrollCommand) { _, command in
                guard let command else { return }
                executeScrollCommand(command, proxy: proxy)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.viewState.mode == .roomDetail {
                messageComposer(containerWidth: containerSize.width)
                    .zIndex(10)
            }
        }
        .overlay(alignment: .bottom) {
            if presenter.viewState.showsNewMessageIndicator {
                newMessageIndicator
                    .padding(.bottom, measuredComposerHeight + composerBottomPadding + PikkoSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        RootTabBarMetrics.contentHeight
    }

    private var newMessageIndicator: some View {
        Button {
            Task { await presenter.send(.newMessageIndicatorTapped) }
        } label: {
            HStack(spacing: PikkoSpacing.xs) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(presenter.viewState.newMessageCount > 1 ? "새 메시지 \(presenter.viewState.newMessageCount)개" : "새 메시지")
                    .font(PikkoTypography.captionStrong)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, PikkoSpacing.md)
            .frame(height: 36)
            .background(PikkoColor.accent)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            HStack(spacing: PikkoSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PikkoColor.secondaryText)

                TextField("메시지 검색", text: searchTextBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.primaryText)

                Button {
                    Task { await presenter.send(.previousSearchResultTapped) }
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 28)
                }
                .disabled(!presenter.viewState.canNavigateSearchResults)

                Button {
                    Task { await presenter.send(.nextSearchResultTapped) }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .disabled(!presenter.viewState.canNavigateSearchResults)
            }

            Text(presenter.viewState.searchStatusText)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
                .lineLimit(2)
        }
        .padding(PikkoSpacing.md)
        .background(PikkoColor.surfaceElevated)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.divider.opacity(0.55), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private func messageComposer(containerWidth: CGFloat) -> some View {
        let isUploadingFiles = presenter.viewState.isUploadingFiles
        let resolvedContainerWidth = max(containerWidth, 0)
        let roomIdExists = presenter.viewState.selectedRoomID != nil
        let inputEnabled = roomIdExists && !presenter.viewState.isSending && !isUploadingFiles
        Logger.shared.debug("[ChatComposer] render visible=true roomIdExists=\(roomIdExists) inputEnabled=\(inputEnabled) reason=roomDetail")
        Logger.shared.debug("[ChatComposer] inputEnabled=\(inputEnabled) reason=\(roomIdExists ? "ready" : "missingRoomId")")
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
                        .foregroundStyle(PikkoColor.primary)
                        .frame(width: 44, height: 44)
                        .background(PikkoColor.primarySoft)
                        .clipShape(Circle())
                }
                .disabled(presenter.viewState.selectedRoomID == nil || isUploadingFiles || presenter.viewState.isSending)

                Button {
                    isFileImporterPresented = true
                } label: {
                    Image(systemName: isUploadingFiles ? "hourglass" : "doc.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PikkoColor.primary)
                        .frame(width: 44, height: 44)
                        .background(PikkoColor.primarySoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(presenter.viewState.selectedRoomID == nil || isUploadingFiles || presenter.viewState.isSending)

                TextField(
                    "메시지 입력",
                    text: messageTextBinding,
                    prompt: Text("메시지 입력")
                        .foregroundStyle(PikkoColor.textTertiary),
                    axis: .vertical
                )
                .lineLimit(1...3)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.primaryText)
                .tint(PikkoColor.primary)
                .padding(.horizontal, PikkoSpacing.md)
                .padding(.vertical, PikkoSpacing.sm + 2)
                .frame(minHeight: 48)
                .background(PikkoColor.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                        .stroke(PikkoColor.primary.opacity(isComposerFocused ? 0.32 : 0.12), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
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
                        .background(presenter.viewState.canSend ? PikkoColor.primary : PikkoColor.gray300)
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
                PikkoColor.background.opacity(0.98)
                    .onAppear {
                        logComposerGeometry(
                            proxy: proxy,
                            containerWidth: resolvedContainerWidth,
                            reason: "onAppear",
                            keyboardVisible: keyboardObserver.isKeyboardVisible
                        )
                    }
                    .onChange(of: proxy.frame(in: .named(CoordinateSpaceName.roomDetailRoot))) { _, _ in
                        logComposerGeometry(
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
            Logger.shared.debug(
                "[ChatComposer] focused=\(focused) bottomTarget=\(keyboardObserver.isKeyboardVisible ? "keyboard" : "tabBarTop")"
            )
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

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { presenter.viewState.searchQuery },
            set: { value in
                Task { await presenter.send(.searchQueryChanged(value)) }
            }
        )
    }

    private func handleImageSelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var files: [ChatUploadFile] = []
        for (index, item) in items.enumerated() {
            guard let rawData = try? await item.loadTransferable(type: Data.self),
                  !rawData.isEmpty else {
                selectedPhotoItems = []
                await presenter.send(.fileSelectionFailed("파일 업로드에 실패했어요. 다시 시도해 주세요."))
                return
            }
            let preferredType = preferredUploadType(from: item.supportedContentTypes)
            let ext = preferredType.preferredFilenameExtension ?? "jpg"
            let mimeType = preferredType.preferredMIMEType ?? "image/jpeg"

            files.append(
                ChatUploadFile(
                    data: rawData,
                    fileName: "chat-\(Int(Date().timeIntervalSince1970))-\(index).\(ext.lowercased())",
                    mimeType: mimeType,
                    typeIdentifier: preferredType.identifier
                )
            )
        }

        selectedPhotoItems = []
        await presenter.send(.filesSelected(files))
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        var files: [ChatUploadFile] = []
        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                await presenter.send(.fileSelectionFailed("파일 업로드에 실패했어요. 다시 시도해 주세요."))
                return
            }
            let type = UTType(filenameExtension: url.pathExtension) ?? .pdf
            files.append(
                ChatUploadFile(
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: type.preferredMIMEType ?? "application/pdf",
                    typeIdentifier: type.identifier
                )
            )
        }
        await presenter.send(.filesSelected(files))
    }

    private func preferredUploadType(from types: [UTType]) -> UTType {
        if let gif = types.first(where: { $0.conforms(to: .gif) }) { return gif }
        if let png = types.first(where: { $0.conforms(to: .png) }) { return png }
        if let jpeg = types.first(where: { $0.conforms(to: .jpeg) }) { return jpeg }
        return types.first(where: { $0.conforms(to: .image) }) ?? .jpeg
    }

    private func executeScrollCommand(_ command: ChatScrollCommand, proxy: ScrollViewProxy) {
        let action = {
            switch command.target {
            case .bottom:
                proxy.scrollTo(ChatBottomAnchor.id, anchor: .bottom)
            case .message(let id):
                proxy.scrollTo(id, anchor: .center)
            }
        }

        Logger.shared.debug("[ChatScroll] execute target=\(command.target.logValue) animated=\(command.animated)")
        if command.animated {
            withAnimation(.easeOut(duration: 0.22)) {
                action()
            }
        } else {
            action()
        }
    }

    private func updateNearBottomState(bottomY: CGFloat, containerHeight: CGFloat) {
        guard bottomY.isFinite, containerHeight.isFinite, containerHeight > 0 else { return }
        let visibleBottom = containerHeight - measuredComposerHeight - composerBottomPadding
        let distance = max(0, bottomY - visibleBottom)
        let nearBottom = distance <= Layout.nearBottomThreshold
        Task {
            await presenter.send(.nearBottomChanged(nearBottom, distance: distance))
        }
    }

    private func updateMeasuredComposerHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        guard abs(measuredComposerHeight - height) > Layout.geometryTolerance else { return }
        measuredComposerHeight = height
#if DEBUG
        guard ChatDebugOptions.isComposerGeometryLoggingEnabled else { return }
        Logger.shared.debug("[ChatComposer] measuredHeight=\(height)")
#endif
    }

    private func logComposerKeyboardState() {
#if DEBUG
        guard ChatDebugOptions.isComposerGeometryLoggingEnabled else { return }
        Logger.shared.debug(
            "[ChatComposer] keyboardHeight=\(keyboardObserver.keyboardHeight) isKeyboardVisible=\(keyboardObserver.isKeyboardVisible)"
        )
        Logger.shared.debug(
            "[ChatComposer] bottomPadding=\(composerBottomPadding) customTabBarHeight=\(keyboardObserver.isKeyboardVisible ? 0 : customTabBarAvoidanceHeight)"
        )
        Logger.shared.debug("[ChatComposer] visible=true")
#endif
    }

    private func logComposerGeometry(
        proxy: GeometryProxy,
        containerWidth: CGFloat,
        reason: String,
        keyboardVisible: Bool
    ) {
        guard isRoomDetailVisible else { return }

        let localFrame = proxy.frame(in: .named(CoordinateSpaceName.roomDetailRoot))
        let screenFrame = proxy.frame(in: .global)
        let expectedWidth = containerWidth
        let bottomTarget = keyboardVisible ? "keyboard" : "tabBarTop"
#if DEBUG
        if ChatDebugOptions.isComposerGeometryLoggingEnabled {
            Logger.shared.debug(
                "[ChatComposer] geometry reason=\(reason) minY=\(localFrame.minY) maxY=\(localFrame.maxY) width=\(localFrame.width) targetWidth=\(expectedWidth) bottomTarget=\(bottomTarget)"
            )
            Logger.shared.debug("[ChatComposer] safeAreaInsets=\(String(describing: proxy.safeAreaInsets))")
            Logger.shared.debug("[ChatComposer] customTabBarHeight=\(keyboardObserver.isKeyboardVisible ? 0 : customTabBarAvoidanceHeight)")
            Logger.shared.debug("[ChatComposer] keyboardVisible=\(keyboardVisible)")
            Logger.shared.debug(
                "[ChatComposer] keyboardHeight=\(keyboardObserver.keyboardHeight) isKeyboardVisible=\(keyboardObserver.isKeyboardVisible)"
            )
            Logger.shared.debug(
                "[ChatComposer] bottomPadding=\(composerBottomPadding) customTabBarHeight=\(keyboardObserver.isKeyboardVisible ? 0 : customTabBarAvoidanceHeight)"
            )
            Logger.shared.debug("[ChatComposer] visible=true")
        }
#endif

        validateComposerVisibility(screenFrame: screenFrame)

        validateComposerHorizontalGeometry(
            frame: localFrame,
            expectedWidth: expectedWidth,
            bottomTarget: bottomTarget,
            reason: reason
        )
    }

    private func validateComposerVisibility(screenFrame: CGRect) {
        let screenBounds = UIScreen.main.bounds
        let hasVisibleHeight = screenFrame.height > 0
            && screenFrame.maxY > screenBounds.minY
            && screenFrame.minY < screenBounds.maxY

        if hasVisibleHeight {
            return
        }

        let reason: String
        if screenFrame.height <= 0 {
            reason = "zeroHeight"
        } else if screenFrame.minY >= screenBounds.maxY {
            reason = "belowScreen"
        } else {
            reason = "aboveScreen"
        }

        Logger.shared.error(
            "[ChatComposer] composerNotVisible reason=\(reason) screenFrame=\(screenFrame.debugDescription) screenBounds=\(screenBounds.debugDescription)"
        )
    }

    private func validateComposerHorizontalGeometry(
        frame: CGRect,
        expectedWidth: CGFloat,
        bottomTarget: String,
        reason: String
    ) {
        guard expectedWidth > 0 else { return }

        let hasInvalidMinX = abs(frame.minX) > Layout.geometryTolerance
        let hasInvalidWidth = abs(frame.width - expectedWidth) > Layout.geometryTolerance
        guard hasInvalidMinX || hasInvalidWidth else {
#if DEBUG
            guard ChatDebugOptions.isComposerGeometryLoggingEnabled else { return }
            Logger.shared.debug(
                "[ChatComposer] geometryValid minX=\(frame.minX) width=\(frame.width) targetWidth=\(expectedWidth) bottomTarget=\(bottomTarget)"
            )
#endif
            return
        }

        Logger.shared.error(
            "[ChatComposer] invalidHorizontalGeometry minX=\(frame.minX) expected=0 width=\(frame.width) expectedWidth=\(expectedWidth) reason=\(reason)"
        )
    }

    private func updateMessageListInsets() {
#if DEBUG
        guard ChatDebugOptions.isComposerGeometryLoggingEnabled else { return }
        Logger.shared.debug(
            "[ChatComposer] messageListBottomInset=\(messageListBottomInset) composerMeasuredHeight=\(measuredComposerHeight) keyboardVisible=\(keyboardObserver.isKeyboardVisible)"
        )
#endif
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
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.divider.opacity(0.55), lineWidth: 1)
        }
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
                Text(highlightedContent)
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
                                .foregroundStyle(message.isMine ? .white : PikkoColor.primaryPressed)
                                .frame(width: 164, height: 40, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, PikkoSpacing.md)
        .padding(.vertical, PikkoSpacing.sm)
        .background(message.isMine ? bubbleColor : PikkoColor.elevatedSurface)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(message.isMine ? .clear : PikkoColor.divider.opacity(0.65), lineWidth: 1)
        }
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
                    .foregroundStyle(message.sendStatus == .failed ? PikkoColor.error : PikkoColor.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private var bubbleColor: Color {
        message.sendStatus == .failed ? PikkoColor.error.opacity(0.78) : PikkoColor.primary
    }

    private var highlightedContent: AttributedString {
        var attributed = AttributedString(message.content)
        for nsRange in message.searchMatchRanges {
            guard let range = Range(nsRange, in: message.content),
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else {
                continue
            }
            let attributedRange = lower..<upper
            attributed[attributedRange].backgroundColor = message.isMine ? .white.opacity(0.28) : .yellow.opacity(0.45)
            attributed[attributedRange].foregroundColor = message.isMine ? .white : PikkoColor.primaryText
        }
        return attributed
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

private enum ChatBottomAnchor {
    static let id = "chat-bottom-anchor"
}

private struct ChatBottomDistancePreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@MainActor
private final class ChatKeyboardObserver: ObservableObject {
    private static var activeObserverID: UUID?

    @Published private(set) var keyboardHeight: CGFloat = 0
    @Published private(set) var isKeyboardVisible = false
    @Published private(set) var animationDuration: Double = 0.25
    @Published private(set) var animationCurve: UInt = 0

    private let observerID = UUID()
    private var willChangeFrameObserver: NSObjectProtocol?
    private var willHideObserver: NSObjectProtocol?
    private var lastLoggedEvent: (name: String, height: CGFloat, timestamp: TimeInterval)?

    func activate() {
        Self.activeObserverID = observerID
        guard willChangeFrameObserver == nil, willHideObserver == nil else { return }

        willChangeFrameObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let payload = KeyboardEventPayload(notification: notification)
            MainActor.assumeIsolated {
                self?.handleKeyboardWillChangeFrame(payload)
            }
        }

        willHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let payload = KeyboardEventPayload(notification: notification)
            MainActor.assumeIsolated {
                self?.handleKeyboardWillHide(payload)
            }
        }
    }

    func deactivate() {
        if let willChangeFrameObserver {
            NotificationCenter.default.removeObserver(willChangeFrameObserver)
            self.willChangeFrameObserver = nil
        }

        if let willHideObserver {
            NotificationCenter.default.removeObserver(willHideObserver)
            self.willHideObserver = nil
        }

        if Self.activeObserverID == observerID {
            Self.activeObserverID = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            deactivate()
        }
    }

    private func handleKeyboardWillChangeFrame(_ payload: KeyboardEventPayload) {
        guard Self.activeObserverID == observerID else { return }
        keyboardHeight = keyboardOverlapHeight(from: payload)
        isKeyboardVisible = keyboardHeight > 0
        animationDuration = payload.animationDuration
        animationCurve = payload.animationCurve
        logKeyboardEventIfNeeded(name: "willChangeFrame", height: keyboardHeight)
    }

    private func handleKeyboardWillHide(_ payload: KeyboardEventPayload) {
        guard Self.activeObserverID == observerID else { return }
        keyboardHeight = 0
        isKeyboardVisible = false
        animationDuration = payload.animationDuration
        animationCurve = payload.animationCurve
        logKeyboardEventIfNeeded(name: "willHide", height: 0)
    }

    private func logKeyboardEventIfNeeded(name: String, height: CGFloat) {
        let now = Date().timeIntervalSince1970
        if let lastLoggedEvent,
           lastLoggedEvent.name == name,
           abs(lastLoggedEvent.height - height) < 0.5,
           now - lastLoggedEvent.timestamp < 0.05 {
            return
        }

        lastLoggedEvent = (name, height, now)
        switch name {
        case "willChangeFrame":
            Logger.shared.debug("[ChatKeyboard] willChangeFrame height=\(height)")
        case "willHide":
            Logger.shared.debug("[ChatKeyboard] willHide")
        default:
            break
        }
    }

    private func keyboardOverlapHeight(from payload: KeyboardEventPayload) -> CGFloat {
        guard let endFrame = payload.endFrame else {
            return 0
        }

        let windowBounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .bounds ?? UIScreen.main.bounds
        return max(0, windowBounds.maxY - endFrame.minY)
    }
}

private struct KeyboardEventPayload: Sendable {
    let endFrame: CGRect?
    let animationDuration: Double
    let animationCurve: UInt

    init(notification: Notification) {
        endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        animationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
    }
}
