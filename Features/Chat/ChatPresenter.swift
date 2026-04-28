import Foundation

@MainActor
final class ChatPresenter: ObservableObject {
    @Published private(set) var viewState = ChatViewState()

    private let interactor: ChatInteracting
    private let router: ChatRouting
    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private let timeFormatter: DateFormatter
    private var hasLoaded = false
    private var rooms: [ChatRoom] = []
    private var messages: [ChatMessage] = []
    private var selectedRoom: ChatRoom?
    private var roomListRequestID = 0
    private var messageRequestID = 0

    init(interactor: ChatInteracting, router: ChatRouting) {
        self.interactor = interactor
        self.router = router
        self.relativeDateFormatter.locale = Locale(identifier: "ko_KR")
        self.relativeDateFormatter.unitsStyle = .short

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        self.timeFormatter = formatter
    }

    func send(_ action: ChatAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState.isExternalDetailPresentation = interactor.startsFromStore
            if interactor.startsFromStore {
                await openStoreRoom()
            } else if interactor.startsFromOpponent {
                viewState.isExternalDetailPresentation = true
                await openUserRoom()
            } else {
                await loadRooms(isRefresh: false)
            }
        case .refreshRequested:
            if viewState.mode == .roomDetail, let roomID = viewState.selectedRoomID {
                await loadMessages(roomID: roomID, isRefresh: true)
            } else {
                await loadRooms(isRefresh: true)
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
            guard !interactor.startsFromStore else { return }
            selectedRoom = nil
            messages = []
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
            rooms = loadedRooms
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
        viewState.title = "문의하기"
        setLoading(isRefresh: false)

        do {
            let room = try await interactor.createOrFetchStoreChatRoom()
            selectedRoom = room
            viewState.selectedRoomID = room.id
            viewState.title = roomTitle(room)
            messages = try await interactor.loadMessages(roomID: room.id, after: nil)
            applyMessages()
        } catch {
            apply(error: error, emptyTitle: "채팅을 시작하지 못했어요", isRefresh: false)
        }

        clearLoading()
    }

    private func openUserRoom() async {
        viewState.mode = .roomDetail
        viewState.title = "채팅"
        setLoading(isRefresh: false)

        do {
            let room = try await interactor.createOrFetchUserChatRoom()
            selectedRoom = room
            viewState.selectedRoomID = room.id
            viewState.title = roomTitle(room)
            messages = try await interactor.loadMessages(roomID: room.id, after: nil)
            applyMessages()
        } catch {
            apply(error: error, emptyTitle: "채팅을 시작하지 못했어요", isRefresh: false)
        }

        clearLoading()
    }

    private func showRoom(_ room: ChatRoom) async {
        viewState.mode = .roomDetail
        viewState.selectedRoomID = room.id
        viewState.title = roomTitle(room)
        await loadMessages(roomID: room.id, isRefresh: false)
    }

    private func loadMessages(roomID: String, isRefresh: Bool) async {
        messageRequestID += 1
        let requestID = messageRequestID
        setLoading(isRefresh: isRefresh)
        defer {
            if requestID == messageRequestID {
                clearLoading()
            }
        }

        do {
            let loadedMessages = try await interactor.loadMessages(roomID: roomID, after: nil)
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

        do {
            let message = try await interactor.sendMessage(roomID: roomID, content: content, files: files)
            merge(message)
            viewState.messageText = ""
            viewState.attachedFilePaths = []
            applyMessages()
        } catch {
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
        messages.removeAll { $0.id == message.id }
        messages.append(message)
        messages.sort {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    private func applyRooms() {
        viewState.mode = .roomList
        viewState.title = "채팅"
        viewState.rooms = rooms.map(makeRoomRow)
        viewState.messages = []
        viewState.selectedRoomID = nil
        viewState.emptyTitle = viewState.rooms.isEmpty ? "아직 채팅방이 없어요" : nil
        viewState.emptyMessage = viewState.rooms.isEmpty ? "가게 상세에서 문의를 시작하면 대화가 여기에 표시돼요." : nil
        viewState.primaryActionTitle = viewState.rooms.isEmpty ? "다시 불러오기" : nil
        viewState.requiresAuthentication = false
    }

    private func applyMessages() {
        viewState.rooms = []
        viewState.messages = messages.map(makeMessageRow)
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

    private func makeMessageRow(_ message: ChatMessage) -> ChatMessageRowViewState {
        ChatMessageRowViewState(
            id: message.id,
            content: message.content,
            filePaths: message.filePaths,
            timeText: message.createdAt.map { timeFormatter.string(from: $0) } ?? "",
            senderName: message.sender.nick,
            isMine: message.sender.id == interactor.currentUserID
        )
    }

    private func roomTitle(_ room: ChatRoom) -> String {
        displayParticipant(for: room)?.nick ?? "채팅"
    }

    private func displayParticipant(for room: ChatRoom) -> ChatParticipant? {
        room.participants.first { $0.id != interactor.currentUserID } ?? room.participants.first
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
