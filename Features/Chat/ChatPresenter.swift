import Combine
import Foundation

@MainActor
final class ChatPresenter: ObservableObject {
    @Published private(set) var viewState = ChatViewState()

    private let interactor: ChatInteracting
    private let router: ChatRouting
    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter
    private var hasLoaded = false
    private var rooms: [ChatRoom] = []
    private var messages: [ChatMessage] = []
    private var selectedRoom: ChatRoom?
    private var roomListRequestID = 0
    private var messageRequestID = 0
    private var realtimeRoomID: String?
    private var currentContext: ChatRoomContext?
    private var cancellables = Set<AnyCancellable>()

    init(interactor: ChatInteracting, router: ChatRouting) {
        self.interactor = interactor
        self.router = router
        self.relativeDateFormatter.locale = Locale(identifier: "ko_KR")
        self.relativeDateFormatter.unitsStyle = .short

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        self.timeFormatter = formatter

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "yyyy년 M월 d일"
        self.dateFormatter = dateFormatter

        bindRoomUpdates()
    }

    func send(_ action: ChatAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState.isExternalDetailPresentation = interactor.target != nil
            switch interactor.target {
            case .store:
                await openStoreRoom()
            case .user:
                await openUserRoom()
            case .room(let roomID, let title, _):
                await openExistingRoom(roomID: roomID, title: title)
            case nil:
                await loadRooms(isRefresh: false)
            }
        case .refreshRequested:
            if viewState.mode == .roomDetail, let roomID = viewState.selectedRoomID {
                await synchronizeMessages(roomID: roomID, isRefresh: true)
            } else {
                await loadRooms(isRefresh: true)
            }
        case .onDisappear:
            if viewState.isExternalDetailPresentation {
                interactor.stopRealtime()
            }
        case .primaryButtonTapped:
            if viewState.requiresAuthentication {
                router.routeToPrimaryDestination()
            } else {
                await send(.refreshRequested)
            }
        case .roomTapped(let roomID):
            guard let room = rooms.first(where: { $0.id == roomID }) else { return }
            selectedRoom = room
            await showRoom(room)
        case .backToRoomsTapped:
            guard interactor.target == nil else { return }
            selectedRoom = nil
            messages = []
            realtimeRoomID = nil
            interactor.stopRealtime()
            viewState.mode = .roomList
            viewState.title = "채팅"
            viewState.messages = []
            applyRooms()
        case .messageTextChanged(let text):
            viewState.messageText = text
        case .filesSelected(let files):
            await upload(files)
        case .attachedFileRemoved(let path):
            viewState.attachedFilePaths.removeAll { $0 == path }
        case .sendMessageTapped:
            await sendMessage()
        }
    }

    private func loadRooms(isRefresh: Bool) async {
        roomListRequestID += 1
        let requestID = roomListRequestID
        setLoading(isRefresh: isRefresh)
        defer {
            if requestID == roomListRequestID {
                clearLoading()
            }
        }

        do {
            let loadedRooms = try await interactor.loadInitialRoomList()
            guard requestID == roomListRequestID else { return }
            rooms = deduplicatedRooms(loadedRooms)
            applyRooms()
            viewState.errorMessage = nil
        } catch is CancellationError {
            guard requestID == roomListRequestID else { return }
        } catch {
            guard requestID == roomListRequestID else { return }
            apply(error: error, emptyTitle: "채팅방을 불러오지 못했어요", isRefresh: isRefresh)
        }
    }

    private func openStoreRoom() async {
        viewState.mode = .roomDetail
        viewState.title = interactor.target?.preferredTitle ?? "문의하기"
        setLoading(isRefresh: false)

        do {
            let room = try await interactor.createOrFetchStoreChatRoom()
            selectedRoom = room
            viewState.selectedRoomID = room.id
            applyContext(interactor.makeContext(for: room, entryPoint: .storeDetail))
            await loadCachedMessagesAndStartLiveSync(roomID: room.id, isRefresh: false)
        } catch {
            apply(error: error, emptyTitle: "채팅을 시작하지 못했어요", isRefresh: false)
        }

        clearLoading()
    }

    private func openUserRoom() async {
        viewState.mode = .roomDetail
        viewState.title = interactor.target?.preferredTitle ?? "채팅"
        setLoading(isRefresh: false)

        do {
            let room = try await interactor.createOrFetchUserChatRoom()
            selectedRoom = room
            viewState.selectedRoomID = room.id
            applyContext(interactor.makeContext(for: room, entryPoint: .userProfile))
            await loadCachedMessagesAndStartLiveSync(roomID: room.id, isRefresh: false)
        } catch {
            apply(error: error, emptyTitle: "채팅을 시작하지 못했어요", isRefresh: false)
        }

        clearLoading()
    }

    private func openExistingRoom(roomID: String, title: String) async {
        viewState.mode = .roomDetail
        viewState.selectedRoomID = roomID
        viewState.title = title
        currentContext = ChatRoomContext(
            entryPoint: .chatList,
            roomID: roomID,
            opponentID: nil,
            storeID: nil,
            displayTitle: title,
            canUseStoreScopedTitle: false
        )
        await loadCachedMessagesAndStartLiveSync(roomID: roomID, isRefresh: false)
    }

    private func showRoom(_ room: ChatRoom) async {
        viewState.mode = .roomDetail
        viewState.selectedRoomID = room.id
        applyContext(interactor.makeContext(for: room, entryPoint: .chatList))
        await loadCachedMessagesAndStartLiveSync(roomID: room.id, isRefresh: false)
    }

    private func loadCachedMessagesAndStartLiveSync(roomID: String, isRefresh: Bool) async {
        messageRequestID += 1
        let requestID = messageRequestID
        setLoading(isRefresh: isRefresh)
        defer {
            if requestID == messageRequestID {
                clearLoading()
            }
        }

        do {
            let cachedMessages = try await interactor.loadCachedMessages(roomID: roomID)
            guard requestID == messageRequestID else { return }
            Logger.shared.debug("[ChatViewModel] loadLocalMessages count=\(cachedMessages.count)")
            messages = cachedMessages
            applyMessages()
        } catch {
            Logger.shared.warning("[Chat] local messages load failed: \(error.localizedDescription)")
        }

        do {
            let loadedMessages = try await interactor.synchronizeMessages(roomID: roomID)
            guard requestID == messageRequestID else { return }
            messages = loadedMessages
            applyMessages()
            viewState.errorMessage = nil
        } catch is CancellationError {
            guard requestID == messageRequestID else { return }
            throwCancellationDebugLog()
            return
        } catch {
            guard requestID == messageRequestID else { return }
            apply(error: error, emptyTitle: "메시지를 불러오지 못했어요", isRefresh: isRefresh)
            return
        }

        guard realtimeRoomID != roomID else { return }
        realtimeRoomID = roomID
        Logger.shared.debug("[ChatViewModel] connectSocket afterSync=true")
        do {
            try await interactor.startRealtime(roomID: roomID) { [weak self] message in
                guard let self, self.viewState.selectedRoomID == message.roomID else { return }
                self.merge(message)
                self.updateRoomList(with: message)
                self.applyMessages()
            }
        } catch {
            Logger.shared.warning("[Chat] realtime connection failed: \(error.localizedDescription)")
        }
    }

    private func synchronizeMessages(roomID: String, isRefresh: Bool) async {
        messageRequestID += 1
        let requestID = messageRequestID
        setLoading(isRefresh: isRefresh)
        defer {
            if requestID == messageRequestID {
                clearLoading()
            }
        }

        do {
            let loadedMessages = try await interactor.synchronizeMessages(roomID: roomID)
            guard requestID == messageRequestID else { return }
            messages = loadedMessages
            applyMessages()
            viewState.errorMessage = nil
        } catch is CancellationError {
            guard requestID == messageRequestID else { return }
        } catch {
            guard requestID == messageRequestID else { return }
            apply(error: error, emptyTitle: "메시지를 불러오지 못했어요", isRefresh: isRefresh)
        }
    }

    private func sendMessage() async {
        guard !viewState.isSending else { return }
        guard let roomID = viewState.selectedRoomID else { return }
        let content = viewState.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = viewState.attachedFilePaths
        guard !content.isEmpty || !files.isEmpty else { return }

        viewState.isSending = true
        viewState.errorMessage = nil
        Logger.shared.debug("[ChatViewModel] sendMessage contentLength=\(content.count) fileCount=\(files.count)")
        var pendingMessageID: String?

        do {
            let pendingMessage = try interactor.makePendingMessage(roomID: roomID, content: content, files: files)
            pendingMessageID = pendingMessage.id
            messages = try await interactor.savePendingMessage(pendingMessage)
            viewState.messageText = ""
            viewState.attachedFilePaths = []
            applyMessages()
            let message = try await interactor.sendMessage(roomID: roomID, content: content, files: files)
            messages = try await interactor.replacePendingMessage(localID: pendingMessage.id, with: message)
            updateRoomList(with: message)
            applyMessages()
        } catch {
            if let pendingMessageID {
                messages = (try? await interactor.markMessageFailed(messageID: pendingMessageID)) ?? messages
                applyMessages()
            }
            viewState.errorMessage = transientErrorMessage(from: error)
        }

        viewState.isSending = false
    }

    private func upload(_ files: [ChatUploadFile]) async {
        guard !viewState.isUploadingFiles,
              let roomID = viewState.selectedRoomID,
              !files.isEmpty else { return }

        viewState.isUploadingFiles = true
        viewState.errorMessage = nil
        defer { viewState.isUploadingFiles = false }

        do {
            let uploadedPaths = try await interactor.uploadFiles(roomID: roomID, files: files)
            viewState.attachedFilePaths.append(contentsOf: uploadedPaths)
        } catch {
            viewState.errorMessage = transientErrorMessage(from: error)
        }
    }

    private func merge(_ message: ChatMessage) {
        if messages.contains(where: { $0.id == message.id }) {
            Logger.shared.debug("[ChatSocket] duplicate ignored chatId=\(message.id)")
            return
        }

        messages.removeAll { $0.id == message.id }
        messages.append(message)
        messages.sort {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    private func throwCancellationDebugLog() {
        Logger.shared.debug("[ChatViewModel] message sync cancelled")
    }

    private func applyRooms() {
        viewState.mode = .roomList
        viewState.title = "채팅"
        rooms = deduplicatedRooms(rooms)
        viewState.rooms = rooms.map(makeRoomRow)
        viewState.messages = []
        viewState.selectedRoomID = nil
        currentContext = nil
        viewState.emptyTitle = viewState.rooms.isEmpty ? "아직 채팅방이 없어요" : nil
        viewState.emptyMessage = viewState.rooms.isEmpty ? "상대방과 대화를 시작하면 여기에 표시돼요." : nil
        viewState.primaryActionTitle = viewState.rooms.isEmpty ? "다시 불러오기" : nil
        viewState.requiresAuthentication = false
    }

    private func applyMessages() {
        viewState.rooms = []
        viewState.messages = makeMessageRows(messages)
        viewState.emptyTitle = viewState.messages.isEmpty ? "아직 대화가 없어요" : nil
        viewState.emptyMessage = viewState.messages.isEmpty ? "첫 메시지를 보내보세요." : nil
        viewState.primaryActionTitle = nil
        viewState.requiresAuthentication = false
    }

    private func apply(error: Error, emptyTitle: String, isRefresh: Bool) {
        let hasExistingContent = !viewState.rooms.isEmpty || !viewState.messages.isEmpty
        if isRefresh && hasExistingContent {
            viewState.errorMessage = transientErrorMessage(from: error)
            return
        }

        viewState.errorMessage = transientErrorMessage(from: error)
        viewState.emptyTitle = emptyTitle
        viewState.emptyMessage = resolveErrorMessage(from: error)
        viewState.primaryActionTitle = (error as? ChatFeatureError) == .authenticationRequired ? "확인" : "다시 시도"
        viewState.requiresAuthentication = (error as? ChatFeatureError) == .authenticationRequired
    }

    private func setLoading(isRefresh: Bool) {
        viewState.errorMessage = nil
        if isRefresh || !viewState.rooms.isEmpty || !viewState.messages.isEmpty {
            viewState.isRefreshing = true
        } else {
            viewState.isLoading = true
        }
    }

    private func clearLoading() {
        viewState.isLoading = false
        viewState.isRefreshing = false
    }

    private func makeRoomRow(_ room: ChatRoom) -> ChatRoomRowViewState {
        let participant = displayParticipant(for: room)
        return ChatRoomRowViewState(
            id: room.id,
            title: participant?.nick ?? "알 수 없는 사용자",
            subtitle: room.lastMessage?.content.nilIfEmpty ?? "대화를 시작해 보세요.",
            timeText: relativeTime(from: room.lastMessage?.createdAt ?? room.updatedAt),
            avatarPath: participant?.profileImagePath
        )
    }

    private func makeMessageRows(_ messages: [ChatMessage]) -> [ChatMessageRowViewState] {
        var previousDay: Date?
        return messages.map { message in
            let date = message.createdAt
            let day = date.map { Calendar.current.startOfDay(for: $0) }
            let shouldShowDate = day != nil && day != previousDay
            previousDay = day ?? previousDay
            return makeMessageRow(message, dateText: shouldShowDate ? date.map(dateFormatter.string(from:)) : nil)
        }
    }

    private func makeMessageRow(_ message: ChatMessage, dateText: String?) -> ChatMessageRowViewState {
        ChatMessageRowViewState(
            id: message.id,
            dateText: dateText,
            content: message.content,
            filePaths: message.filePaths,
            timeText: message.createdAt.map { timeFormatter.string(from: $0) } ?? "",
            senderName: message.sender.nick,
            isMine: message.sender.id == interactor.currentUserID,
            sendStatus: message.sendStatus
        )
    }

    private func roomTitle(_ room: ChatRoom) -> String {
        displayParticipant(for: room)?.nick ?? "채팅"
    }

    private func displayParticipant(for room: ChatRoom) -> ChatParticipant? {
        room.participants.first { $0.id != interactor.currentUserID } ?? room.participants.first
    }

    private func bindRoomUpdates() {
        NotificationCenter.default.publisher(for: .pikkoChatRoomDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let message = notification.userInfo?[ChatRoomUpdateNotificationKey.message] as? ChatMessage else {
                    return
                }
                self.updateRoomList(with: message)
                if self.viewState.mode == .roomList {
                    self.applyRooms()
                }
            }
            .store(in: &cancellables)
    }

    private func updateRoomList(with message: ChatMessage) {
        guard let index = rooms.firstIndex(where: { $0.id == message.roomID }) else {
            return
        }
        rooms[index] = rooms[index].updating(lastMessage: message)
        rooms = deduplicatedRooms(rooms)
    }

    private func applyContext(_ context: ChatRoomContext) {
        currentContext = context
        viewState.title = context.displayTitle
        if context.storeID != nil && !context.canUseStoreScopedTitle {
            Logger.shared.debug(
                "[ChatRoomContext] storeScopedTitle disabled roomId=\(context.roomID) storeId=\(context.storeID ?? "-") title=\(context.displayTitle)"
            )
        }
    }

    private func deduplicatedRooms(_ rooms: [ChatRoom]) -> [ChatRoom] {
        var byID: [String: ChatRoom] = [:]
        for room in rooms {
            if let existing = byID[room.id] {
                byID[room.id] = preferredRoom(existing, room)
            } else {
                byID[room.id] = room
            }
        }
        return byID.values.sorted { lhs, rhs in
            latestActivityDate(lhs) > latestActivityDate(rhs)
        }
    }

    private func preferredRoom(_ lhs: ChatRoom, _ rhs: ChatRoom) -> ChatRoom {
        if lhs.lastMessage == nil, rhs.lastMessage != nil {
            return rhs
        }
        if rhs.lastMessage == nil, lhs.lastMessage != nil {
            return lhs
        }
        return latestActivityDate(rhs) > latestActivityDate(lhs) ? rhs : lhs
    }

    private func latestActivityDate(_ room: ChatRoom) -> Date {
        room.lastMessage?.createdAt ?? room.updatedAt ?? room.createdAt ?? .distantPast
    }

    private func relativeTime(from date: Date?) -> String {
        guard let date else { return "" }
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func transientErrorMessage(from error: Error) -> String? {
        guard let chatError = error as? ChatFeatureError else {
            return nil
        }

        switch chatError {
        case .networkUnavailable:
            return resolveErrorMessage(from: error)
        case .authenticationRequired, .unavailable:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
