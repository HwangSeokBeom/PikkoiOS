import Combine
import Foundation

@MainActor
final class ChatPresenter: ObservableObject {
    @Published private(set) var viewState = ChatViewState()

    private let interactor: ChatInteracting
    private let router: ChatRouting
    private let notificationService: AppNotificationService
    private let activeChatRoomTracker: ActiveChatRoomTracking
    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter
    private var hasLoaded = false
    private var serverRooms: [ChatRoom] = []
    private var localConversationSummaries: [ChatLocalConversationSummary] = []
    private var listEntries: [ChatListEntry] = []
    private var visibleServerRoomCount = ChatRoomListPaginationPolicy.defaultPageSize
    private var messages: [ChatMessage] = []
    private var selectedRoom: ChatRoom?
    private var roomListRequestID = 0
    private var messageRequestID = 0
    private var realtimeRoomID: String?
    private var currentContext: ChatRoomContext?
    private var isNearBottom = true
    private var scrollCommandID = 0
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lifecycle: ChatRoomLifecycleState = .idle

    init(
        interactor: ChatInteracting,
        router: ChatRouting,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        activeChatRoomTracker: ActiveChatRoomTracking = ActiveChatRoomTracker()
    ) {
        self.interactor = interactor
        self.router = router
        self.notificationService = notificationService
        self.activeChatRoomTracker = activeChatRoomTracker
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

    deinit {
        searchTask?.cancel()
        guard hasLoaded else { return }
        Logger.shared.debug("[ChatRoute] deallocated roomId=-")
        Logger.shared.debugVerbose("[ChatViewModel] deinit")
    }

    func send(_ action: ChatAction) async {
        switch action {
        case .onAppear(let instanceID, let presentationKind):
            Logger.shared.debug(
                "[ChatRootView] appear roomId=\(debugRouteRoomID) source=\(debugRouteSource) instanceId=\(instanceID) presentationKind=\(presentationKind.rawValue)"
            )
            guard !hasLoaded else {
                await resumeRealtimeIfNeeded()
                return
            }
            hasLoaded = true
            viewState.isExternalDetailPresentation = interactor.target != nil
            switch interactor.target {
            case .store:
                await openStoreRoom()
            case .user:
                await openUserRoom()
            case .room(let roomID, let title, _, let source, let storeID, let opponentID):
                await openExistingRoom(
                    roomID: roomID,
                    title: title,
                    source: source,
                    storeID: storeID,
                    opponentID: opponentID
                )
            case nil:
                await loadRooms(isRefresh: false)
            }
        case .refreshRequested:
            if viewState.mode == .roomDetail, let roomID = viewState.selectedRoomID {
                await synchronizeMessages(scope: currentScope(roomID: roomID), isRefresh: true)
            } else {
#if DEBUG
                if viewState.roomListSearch.isActive {
                    Logger(category: "ChatRoomSearch").debug("[ChatRoomSearch] reload requested")
                }
#endif
                await loadRooms(isRefresh: true)
            }
        case .onDisappear(let instanceID, let presentationKind):
            Logger.shared.debug(
                "[ChatRootView] disappear roomId=\(viewState.selectedRoomID ?? debugRouteRoomID) source=\(debugRouteSource) instanceId=\(instanceID) presentationKind=\(presentationKind.rawValue)"
            )
            handleDisappear()
        case .primaryButtonTapped:
            if viewState.requiresAuthentication {
                router.routeToPrimaryDestination()
            } else {
                await send(.refreshRequested)
            }
        case .roomTapped(let roomID):
            guard let entry = listEntries.first(where: { $0.id == roomID }) else { return }
            switch entry {
            case .storeScoped(let summary):
                await openChatRoom(roomID: summary.serverRoomID, source: .storeScopedChatList) {
                    selectedRoom = nil
                    await showLocalConversation(summary)
                }
            case .server(let room):
                await openChatRoom(roomID: room.id, source: .chatList) {
                    selectedRoom = room
                    await showRoom(room)
                }
            }
        case .backToRoomsTapped:
            popChatRoom(reason: "backButton")
        case .messageTextChanged(let text):
            viewState.messageText = text
        case .activateRoomListSearch:
            activateRoomListSearch()
        case .roomListSearchQueryChanged(let query):
            updateRoomListSearchQuery(query)
        case .cancelRoomListSearch:
            cancelRoomListSearch()
        case .searchTapped:
            activateSearch()
        case .searchDismissed:
            deactivateSearch()
        case .clearSearchQuery:
            updateSearchQuery("")
        case .searchQueryChanged(let query):
            updateSearchQuery(query)
        case .nextSearchResultTapped:
            selectSearchResult(offset: 1)
        case .previousSearchResultTapped:
            selectSearchResult(offset: -1)
        case .searchResultTapped(let id):
            selectSearchResult(id: id)
        case .filesSelected(let files):
            await upload(files)
        case .fileSelectionFailed(let message):
            viewState.errorMessage = message
        case .attachedFileRemoved(let path):
            viewState.attachedFilePaths.removeAll { $0 == path }
        case .sendMessageTapped:
            await sendMessage()
        case .retryMessageTapped(let messageID):
            await retryMessage(messageID: messageID)
        case .roomListReachedEnd:
            loadNextRoomPageIfNeeded()
        case .nearBottomChanged(let nearBottom, let distance):
            guard isNearBottom != nearBottom else { return }
            isNearBottom = nearBottom
            Logger.shared.debug("[ChatScrollState] nearBottom=\(nearBottom) distance=\(distance)")
            if nearBottom {
                viewState.showsNewMessageIndicator = false
                viewState.newMessageCount = 0
            }
        case .newMessageIndicatorTapped:
            viewState.showsNewMessageIndicator = false
            viewState.newMessageCount = 0
            enqueueScroll(target: .bottom, reason: "newMessageIndicator", animated: true)
        }
    }

    private func loadRooms(isRefresh: Bool) async {
        if isRefresh {
            guard !viewState.isRefreshing else { return }
        } else {
            guard !viewState.isInitialLoading, !hasLoaded || serverRooms.isEmpty else { return }
        }
        roomListRequestID += 1
        let requestID = roomListRequestID
        visibleServerRoomCount = ChatRoomListPaginationPolicy.defaultPageSize
#if DEBUG
        Logger(category: "ChatRoomList").debug("[ChatRoomList] initialLoad limit=\(ChatRoomListPaginationPolicy.defaultPageSize) serverPagination=unsupported")
#endif
        setLoading(isRefresh: isRefresh)
        defer {
            if requestID == roomListRequestID {
                clearLoading()
            }
        }

        do {
            let loadedRooms = try await interactor.loadInitialRoomList()
            let loadedLocalConversationSummaries = try await interactor.loadLocalConversationSummaries()
            guard requestID == roomListRequestID else { return }
            let beforeCount = serverRooms.count
            serverRooms = deduplicatedRooms(loadedRooms)
#if DEBUG
            let dedupedCount = max(0, loadedRooms.count - serverRooms.count)
            Logger(category: "ChatRoomList").debug("[ChatRoomList] merge before=\(beforeCount) incoming=\(loadedRooms.count) after=\(serverRooms.count) deduped=\(dedupedCount)")
#endif
            localConversationSummaries = loadedLocalConversationSummaries
            viewState.roomListSearch.hasCompletedInitialLoad = true
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
        transitionLifecycle(to: .entering(roomID: "pending-store"), reason: "storeTarget")
        viewState.mode = .roomDetail
        viewState.title = interactor.target?.preferredTitle ?? "문의하기"
        setLoading(isRefresh: false)

        do {
            let room = try await interactor.createOrFetchStoreChatRoom()
            transitionLifecycle(to: .entering(roomID: room.id), reason: "storeRoomResolved")
            selectedRoom = room
            viewState.selectedRoomID = room.id
            applyContext(interactor.makeContext(for: room, entryPoint: .storeDetail))
            await loadCachedMessagesAndStartLiveSync(scope: currentScope(roomID: room.id), isRefresh: false)
        } catch {
            transitionLifecycle(to: .idle, reason: "storeOpenFailed")
            apply(error: error, emptyTitle: "채팅을 시작하지 못했어요", isRefresh: false)
        }

        clearLoading()
    }

    private func openUserRoom() async {
        transitionLifecycle(to: .entering(roomID: "pending-user"), reason: "userTarget")
        viewState.mode = .roomDetail
        viewState.title = interactor.target?.preferredTitle ?? "채팅"
        setLoading(isRefresh: false)

        do {
            let room = try await interactor.createOrFetchUserChatRoom()
            transitionLifecycle(to: .entering(roomID: room.id), reason: "userRoomResolved")
            selectedRoom = room
            viewState.selectedRoomID = room.id
            applyContext(interactor.makeContext(for: room, entryPoint: .userProfile))
            await loadCachedMessagesAndStartLiveSync(scope: currentScope(roomID: room.id), isRefresh: false)
        } catch {
            transitionLifecycle(to: .idle, reason: "userOpenFailed")
            apply(error: error, emptyTitle: "채팅을 시작하지 못했어요", isRefresh: false)
        }

        clearLoading()
    }

    private func openExistingRoom(
        roomID: String,
        title: String,
        source: ChatRoomEntryPoint,
        storeID: String?,
        opponentID: String?
    ) async {
        Logger.shared.debug("[ChatNavigation] open requested roomId=\(roomID) source=\(source.logValue)")
        guard canOpenRoom(roomID) else { return }
        if viewState.mode == .roomDetail, viewState.selectedRoomID == roomID {
            Logger.shared.debug("[ChatNavigation] open skipped reason=alreadyTop roomId=\(roomID)")
            return
        }
        transitionLifecycle(to: .entering(roomID: roomID), reason: "routeOpen")
        Logger.shared.debug("[ChatNavigation] stateUpdate roomId=\(roomID) source=\(source.logValue) navigationSideEffect=false")
        let cachedContext = interactor.cachedStoreContext(roomID: roomID)
        let displayTitle = title.nilIfEmpty
            ?? cachedContext?.storeName.nilIfEmpty
            ?? "채팅"
        viewState.mode = .roomDetail
        viewState.selectedRoomID = roomID
        if let hydratedRoom = try? await interactor.loadRoom(roomID: roomID) {
            guard isCurrentRoomLifecycle(roomID) else {
                logStaleUpdateIgnored(source: "loadRoom", roomID: roomID)
                return
            }
            var context = interactor.makeContext(for: hydratedRoom, entryPoint: source)
            if context.displayTitle == "채팅", displayTitle != "채팅" {
                context = ChatRoomContext(
                    entryPoint: context.entryPoint,
                    roomID: context.roomID,
                    opponentID: opponentID?.nilIfEmpty ?? context.opponentID,
                    storeID: storeID?.nilIfEmpty ?? context.storeID,
                    storeName: context.storeName,
                    displayTitle: displayTitle,
                    canUseStoreScopedTitle: context.canUseStoreScopedTitle,
                    hasRoomIDCollision: context.hasRoomIDCollision,
                    collidingStoreIDs: context.collidingStoreIDs
                )
            }
            applyContext(context)
            Logger.shared.debug("[ChatRouteHydration] complete roomId=\(roomID) contextRecovered=true navigationSideEffect=false")
        } else {
            guard isCurrentRoomLifecycle(roomID) else {
                logStaleUpdateIgnored(source: "loadRoom", roomID: roomID)
                return
            }
            if source == .unknown {
                Logger.shared.warning("[ChatRoute] missingSource fallback=unknown roomId=\(roomID)")
            }
            applyContext(ChatRoomContext(
                entryPoint: source,
                roomID: roomID,
                opponentID: opponentID?.nilIfEmpty ?? cachedContext?.opponentID.nilIfEmpty,
                storeID: storeID?.nilIfEmpty ?? cachedContext?.storeID.nilIfEmpty,
                storeName: cachedContext?.storeName.nilIfEmpty,
                displayTitle: displayTitle,
                canUseStoreScopedTitle: storeID?.nilIfEmpty != nil || cachedContext?.storeName.nilIfEmpty != nil,
                hasRoomIDCollision: false,
                collidingStoreIDs: []
            ))
            Logger.shared.debug("[ChatRouteHydration] complete roomId=\(roomID) contextRecovered=\(cachedContext != nil || storeID?.nilIfEmpty != nil || opponentID?.nilIfEmpty != nil) navigationSideEffect=false")
        }
        await loadCachedMessagesAndStartLiveSync(scope: currentScope(roomID: roomID), isRefresh: false)
    }

    private func openChatRoom(
        roomID: String,
        source: ChatRoomEntryPoint,
        operation: () async -> Void
    ) async {
        let normalizedRoomID = normalizedRouteRoomID(from: roomID)
        Logger.shared.debug("[ChatNavigation] open requested roomId=\(normalizedRoomID) source=\(source.logValue)")

        if viewState.mode == .roomDetail, viewState.selectedRoomID == normalizedRoomID {
            Logger.shared.debug("[ChatNavigation] open skipped reason=alreadyTop roomId=\(normalizedRoomID)")
            return
        }

        guard canOpenRoom(normalizedRoomID) else { return }
        transitionLifecycle(to: .entering(roomID: normalizedRoomID), reason: "listTap")
        await operation()
    }

    private func popChatRoom(reason: String) {
        let topRoomID = viewState.mode == .roomDetail ? viewState.selectedRoomID : nil
        Logger.shared.debug("[ChatNavigation] pop requested reason=\(reason) top=\(topRoomID ?? "nil")")
        guard interactor.target == nil else { return }
        if case .leaving(let roomID) = lifecycle {
            Logger.shared.debug("[ChatNavigationGuard] leave ignored reason=alreadyLeaving roomId=\(roomID)")
            Logger.shared.debug("[ChatLifecycle] leave ignored reason=alreadyLeaving roomId=\(roomID)")
            return
        }
        guard viewState.mode == .roomDetail else {
            Logger.shared.debug("[ChatNavigation] pop completed remainingTop=roomList")
            return
        }

        if let topRoomID {
            transitionLifecycle(to: .leaving(roomID: topRoomID), reason: reason)
        }
        cancelRoomTasks(reason: reason)
        selectedRoom = nil
        messages = []
        isNearBottom = true
        realtimeRoomID = nil
        messageRequestID += 1
        activeChatRoomTracker.activeRoomId = nil
        interactor.stopRealtime()
        viewState.mode = .roomList
        viewState.title = "채팅"
        viewState.messages = []
        viewState.isLoading = false
        viewState.isRefreshing = false
        viewState.showsNewMessageIndicator = false
        viewState.newMessageCount = 0
        applyRooms()
        transitionLifecycle(to: .idle, reason: "roomListVisible")
        Logger.shared.debug("[ChatNavigationGuard] popOnce routeBefore=roomDetail routeAfter=roomList")
        Logger.shared.debug("[ChatNavigation] pop completed remainingTop=roomList activeRoomId=nil")
        Logger.shared.debug("[ChatNavigation] state cleared selectedRoom=false pendingDeepLink=false activeRoomId=nil")
    }

    private func showRoom(_ room: ChatRoom) async {
        guard viewState.selectedRoomID != room.id || viewState.mode != .roomDetail else {
            Logger.shared.debug("[ChatNavigation] open skipped reason=alreadyTop roomId=\(room.id)")
            return
        }
        viewState.mode = .roomDetail
        viewState.selectedRoomID = room.id
        applyContext(interactor.makeContext(for: room, entryPoint: .chatList))
        await loadCachedMessagesAndStartLiveSync(scope: currentScope(roomID: room.id), isRefresh: false)
    }

    private func showLocalConversation(_ summary: ChatLocalConversationSummary) async {
        if viewState.mode == .roomDetail,
           viewState.selectedRoomID == summary.serverRoomID {
            Logger.shared.debug("[ChatNavigation] open skipped reason=alreadyTop roomId=\(summary.serverRoomID)")
            return
        }
        viewState.mode = .roomDetail
        viewState.selectedRoomID = summary.serverRoomID
        applyContext(interactor.makeContext(for: summary))
        await loadCachedMessagesAndStartLiveSync(scope: summary.scope, isRefresh: false)
    }

    private func loadCachedMessagesAndStartLiveSync(scope: ChatRoomScope, isRefresh: Bool) async {
        messageRequestID += 1
        let requestID = messageRequestID
        let roomID = scope.roomID
        setLoading(isRefresh: isRefresh)
        defer {
            if requestID == messageRequestID, isCurrentRoomLifecycle(roomID) {
                clearLoading()
            }
        }

        do {
            let cachedMessages = try await interactor.loadCachedMessages(scope: scope)
            guard requestID == messageRequestID, isCurrentRoomLifecycle(roomID) else {
                logStaleUpdateIgnored(source: "loadLocalMessages", roomID: roomID)
                return
            }
            Logger.shared.debug("[ChatViewModel] loadLocalMessages count=\(cachedMessages.count) scope=\(scope.localCacheKey)")
            messages = cachedMessages
            applyMessages()
        } catch {
            Logger.shared.warning("[Chat] local messages load failed: \(error.localizedDescription)")
        }

        do {
            let loadedMessages = try await interactor.synchronizeMessages(scope: scope)
            guard requestID == messageRequestID, isCurrentRoomLifecycle(roomID) else {
                logStaleUpdateIgnored(source: "syncLatestMessages", roomID: roomID)
                return
            }
            messages = loadedMessages
            applyMessages()
            enqueueInitialScroll()
            if currentContext?.hasRoomIDCollision != true {
                viewState.errorMessage = nil
            }
        } catch is CancellationError {
            guard requestID == messageRequestID, isCurrentRoomLifecycle(roomID) else { return }
            throwCancellationDebugLog()
            return
        } catch {
            guard requestID == messageRequestID, isCurrentRoomLifecycle(roomID) else {
                logStaleUpdateIgnored(source: "syncLatestMessages", roomID: roomID)
                return
            }
            apply(error: error, emptyTitle: "메시지를 불러오지 못했어요", isRefresh: isRefresh)
            return
        }

        guard isCurrentRoomLifecycle(roomID) else {
            logStaleUpdateIgnored(source: "connectSocket", roomID: roomID)
            return
        }
        guard realtimeRoomID != scope.roomID else {
            Logger.shared.debug("[ChatViewModel] connectSocket skipped reason=alreadyActive roomId=\(scope.roomID)")
            return
        }
        Logger.shared.debug("[ChatViewModel] connectSocket afterSync=true scope=\(scope.localCacheKey)")
        do {
            try await interactor.startRealtime(scope: scope) { [weak self] message in
                guard let self, self.viewState.selectedRoomID == message.roomID, self.lifecycle == .active(roomID: message.roomID) else {
                    Logger.shared.debug("[ChatLifecycle] stale update ignored source=socketMessage roomId=\(message.roomID)")
                    return
                }
                self.handleIncomingMessageNotification(message)
                self.merge(message)
                self.updateRoomList(with: message)
                self.applyMessages()
                self.applyScrollPolicyForReceivedMessage(message)
            } onReconnect: { [weak self] in
                guard let self,
                      self.viewState.selectedRoomID == scope.roomID,
                      self.lifecycle == .active(roomID: scope.roomID) else {
                    Logger.shared.debug("[ChatLifecycle] stale update ignored source=socketReconnect roomId=\(scope.roomID)")
                    return
                }
                Logger.shared.debug("[ChatSync] reason=reconnect lastKnown=latestServerCreatedAt fetched=unknown merged=unknown roomScopeKey=\(scope.roomScopeKey)")
                await self.synchronizeMessages(scope: scope, isRefresh: true)
            }
            guard isCurrentRoomLifecycle(roomID) else {
                interactor.stopRealtime()
                logStaleUpdateIgnored(source: "socketConnected", roomID: roomID)
                return
            }
            realtimeRoomID = scope.roomID
        } catch {
            if realtimeRoomID == scope.roomID {
                realtimeRoomID = nil
            }
            Logger.shared.warning("[Chat] realtime connection failed: \(error.localizedDescription)")
        }
    }

    private func resumeRealtimeIfNeeded() async {
        guard viewState.mode == .roomDetail,
              let roomID = viewState.selectedRoomID,
              realtimeRoomID == nil else {
            return
        }

        Logger.shared.debug("[ChatViewModel] resumeRealtime roomId=\(roomID)")
        await loadCachedMessagesAndStartLiveSync(scope: currentScope(roomID: roomID), isRefresh: false)
    }

    private func handleDisappear() {
        guard viewState.mode == .roomDetail,
              realtimeRoomID != nil else {
            return
        }

        Logger.shared.debug("[ChatViewModel] disconnectSocket reason=viewDisappear roomId=\(realtimeRoomID ?? "-")")
        realtimeRoomID = nil
        activeChatRoomTracker.activeRoomId = nil
        interactor.stopRealtime()
    }

    private func synchronizeMessages(scope: ChatRoomScope, isRefresh: Bool) async {
        messageRequestID += 1
        let requestID = messageRequestID
        setLoading(isRefresh: isRefresh)
        defer {
            if requestID == messageRequestID {
                clearLoading()
            }
        }

        do {
            let loadedMessages = try await interactor.synchronizeMessages(scope: scope)
            guard requestID == messageRequestID, isCurrentRoomLifecycle(scope.roomID) else {
                logStaleUpdateIgnored(source: "syncLatestMessages", roomID: scope.roomID)
                return
            }
            messages = loadedMessages
            applyMessages()
            enqueueScroll(target: .bottom, reason: "refresh", animated: false)
            if currentContext?.hasRoomIDCollision != true {
                viewState.errorMessage = nil
            }
        } catch is CancellationError {
            guard requestID == messageRequestID, isCurrentRoomLifecycle(scope.roomID) else { return }
        } catch {
            guard requestID == messageRequestID, isCurrentRoomLifecycle(scope.roomID) else {
                logStaleUpdateIgnored(source: "syncLatestMessages", roomID: scope.roomID)
                return
            }
            apply(error: error, emptyTitle: "메시지를 불러오지 못했어요", isRefresh: isRefresh)
        }
    }

    private func sendMessage() async {
        guard !viewState.isSending else { return }
        guard let roomID = viewState.selectedRoomID else { return }
        guard lifecycle == .active(roomID: roomID) else {
            logStaleUpdateIgnored(source: "sendMessage", roomID: roomID)
            return
        }
        let content = viewState.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = viewState.attachedFilePaths
        guard !content.isEmpty || !files.isEmpty else { return }

        viewState.isSending = true
        viewState.errorMessage = nil
        defer { viewState.isSending = false }
        var pendingMessageID: String?

        do {
            let pendingMessage = try interactor.makePendingMessage(roomID: roomID, content: content, files: files)
            let localTemporaryID = pendingMessage.effectiveLocalTemporaryID ?? pendingMessage.id
            let clientMessageID = pendingMessage.clientMessageID ?? "-"
            pendingMessageID = localTemporaryID
            let scope = currentScope(roomID: roomID)
            Logger.shared.debug("[ChatSend] localTemporaryId=\(localTemporaryID) clientMessageId=\(clientMessageID) roomScopeKey=\(scope.roomScopeKey) action=optimisticAppend")
            Logger.shared.debug("[ChatSend] start roomId=\(roomID) localTemporaryId=\(localTemporaryID) clientMessageId=\(clientMessageID) contentLength=\(content.count)")

            if !messages.contains(where: { $0.effectiveLocalTemporaryID == localTemporaryID }) {
                messages = ChatMessageMergePolicy.merged(
                    existing: messages,
                    incoming: pendingMessage,
                    currentUserID: interactor.currentUserID,
                    source: "send",
                    roomScopeKey: scope.roomScopeKey
                )
            }
            messages = try await interactor.savePendingMessage(pendingMessage, scope: scope)
            viewState.messageText = ""
            viewState.attachedFilePaths = []
            Logger.shared.debug("[ChatSend] optimisticAppend localTemporaryId=\(localTemporaryID) clientMessageId=\(clientMessageID) messageCount=\(messages.count)")
            applyMessages()
            applyScrollAction(.optimisticAppend, localTemporaryId: localTemporaryID)
            let message = try await interactor.sendMessage(scope: scope, pendingMessage: pendingMessage)
            guard lifecycle == .active(roomID: roomID) else {
                logStaleUpdateIgnored(source: "sendMessage", roomID: roomID)
                return
            }
            let serverChatID = message.effectiveServerChatID ?? message.id
            Logger.shared.debug("[ChatSend] postSuccess localTemporaryId=\(localTemporaryID) clientMessageId=\(clientMessageID) serverChatId=\(serverChatID)")
            if messages.contains(where: { $0.effectiveServerChatID == serverChatID }) {
#if DEBUG
                if ChatDebugOptions.isMergeLoggingEnabled {
                    DebugLogDeduplicator.shared.printOnce(
                        key: "ChatMerge.skipDuplicate.\(serverChatID).post",
                        message: "[ChatMerge] skipDuplicate serverChatId=\(serverChatID) source=post"
                    )
                }
#endif
            } else {
#if DEBUG
                if ChatDebugOptions.isMergeLoggingEnabled {
                    DebugLogDeduplicator.shared.printOnce(
                        key: "ChatMerge.replaceOptimistic.\(localTemporaryID).\(serverChatID).post",
                        message: "[ChatMerge] replaceOptimistic localTemporaryId=\(localTemporaryID) serverChatId=\(serverChatID) source=post"
                    )
                }
#endif
            }
            messages = try await interactor.replacePendingMessage(localID: localTemporaryID, with: message, scope: scope)
            updateRoomList(with: message)
            applyMessages()
            applyScrollAction(.echoReplace(localTemporaryId: localTemporaryID), localTemporaryId: localTemporaryID)
        } catch {
            guard lifecycle == .active(roomID: roomID) else {
                logStaleUpdateIgnored(source: "sendMessage", roomID: roomID)
                return
            }
            if let pendingMessageID {
                messages = (try? await interactor.markMessageFailed(messageID: pendingMessageID, scope: currentScope(roomID: roomID))) ?? messages
                applyMessages()
            }
            viewState.errorMessage = transientErrorMessage(from: error)
        }
    }

    private func retryMessage(messageID: String) async {
        guard let failedMessage = messages.first(where: {
            $0.renderID == messageID
                || $0.id == messageID
                || $0.effectiveLocalTemporaryID == messageID
                || $0.clientMessageID == messageID
        }) else { return }
        guard failedMessage.sendStatus == .failed || failedMessage.sendStatus == .failedAuth || failedMessage.sendStatus == .recoveryNeeded else {
            return
        }
        guard lifecycle == .active(roomID: failedMessage.roomID) else {
            logStaleUpdateIgnored(source: "retryMessage", roomID: failedMessage.roomID)
            return
        }

        let scope = currentScope(roomID: failedMessage.roomID)
        let localTemporaryID = failedMessage.effectiveLocalTemporaryID ?? failedMessage.id
        Logger.shared.debug("[ChatRetry] tapped localTemporaryId=\(localTemporaryID) reason=\(failedMessage.sendStatus.rawValue)")
        if !failedMessage.filePaths.isEmpty {
            Logger.shared.debug("[ChatRetry] reuseUploadedFile=true fileURL=\(failedMessage.filePaths.joined(separator: ","))")
        }

        do {
            let retryingMessages = try? await interactor.updateMessageSendStatus(
                messageID: localTemporaryID,
                status: .retrying,
                scope: scope
            )
            if let retryingMessages, !retryingMessages.isEmpty {
                messages = retryingMessages
            } else {
                messages = messages.map {
                    $0.renderID == failedMessage.renderID ? $0.replacingIdentity(sendStatus: .retrying) : $0
                }
            }
            applyMessages()

            let sentMessage = try await interactor.sendMessage(scope: scope, pendingMessage: failedMessage.replacingIdentity(sendStatus: .retrying))
            let serverChatID = sentMessage.effectiveServerChatID ?? sentMessage.id
            Logger.shared.debug("[ChatSend] postSuccess localTemporaryId=\(localTemporaryID) clientMessageId=\(failedMessage.clientMessageID ?? "-") serverChatId=\(serverChatID)")
            messages = try await interactor.replacePendingMessage(localID: localTemporaryID, with: sentMessage, scope: scope)
            updateRoomList(with: sentMessage)
            applyMessages()
            applyScrollAction(.echoReplace(localTemporaryId: localTemporaryID), localTemporaryId: localTemporaryID)
        } catch {
            messages = (try? await interactor.markMessageFailed(messageID: localTemporaryID, scope: scope)) ?? messages
            applyMessages()
            viewState.errorMessage = transientErrorMessage(from: error)
        }
    }

    private func upload(_ files: [ChatUploadFile]) async {
        guard !viewState.isUploadingFiles,
              let roomID = viewState.selectedRoomID,
              !files.isEmpty else { return }
        guard lifecycle == .active(roomID: roomID) else {
            logStaleUpdateIgnored(source: "upload", roomID: roomID)
            return
        }

        viewState.isUploadingFiles = true
        viewState.errorMessage = nil
        defer { viewState.isUploadingFiles = false }

        do {
            try ChatUploadValidator.validateFileCount(
                existingCount: viewState.attachedFilePaths.count,
                incomingCount: files.count
            )
#if DEBUG
            Logger(category: "ChatUpload").debug("[ChatUpload] validate start fileCount=\(files.count) attachedCount=\(viewState.attachedFilePaths.count)")
#endif
            let uploadedPaths = try await interactor.uploadFiles(roomID: roomID, files: files)
            guard lifecycle == .active(roomID: roomID) else {
                logStaleUpdateIgnored(source: "upload", roomID: roomID)
                return
            }
            viewState.attachedFilePaths.append(contentsOf: uploadedPaths)
#if DEBUG
            Logger(category: "ChatUpload").debug("[ChatUpload] success roomId=\(roomID) fileURL=\(uploadedPaths.joined(separator: ",")) contentType=serverResponse")
#endif
        } catch {
            guard lifecycle == .active(roomID: roomID) else {
                logStaleUpdateIgnored(source: "upload", roomID: roomID)
                return
            }
            viewState.errorMessage = uploadErrorMessage(from: error)
#if DEBUG
            Logger(category: "ChatUpload").warning("[ChatUpload] failed roomId=\(roomID) reason=\(viewState.errorMessage ?? error.localizedDescription)")
#endif
        }
    }

    private func merge(_ message: ChatMessage) {
        let scopeKey = currentScope(roomID: message.roomID).roomScopeKey
        messages = ChatMessageMergePolicy.merged(
            existing: messages,
            incoming: message,
            currentUserID: interactor.currentUserID,
            source: "socket",
            roomScopeKey: scopeKey
        )
    }

    private func throwCancellationDebugLog() {
        Logger.shared.debug("[ChatViewModel] message sync cancelled")
    }

    private func applyRooms() {
        if case .leaving = lifecycle {
            // popChatRoom owns the final idle transition after the room list is
            // rendered, so duplicate list updates cannot reopen the previous room.
        } else {
            transitionLifecycle(to: .idle, reason: "roomListApplied")
        }
        viewState.mode = .roomList
        viewState.title = "채팅"
        serverRooms = deduplicatedRooms(serverRooms)
        let visibleServerRooms = Array(serverRooms.prefix(visibleServerRoomCount))
        listEntries = makeListEntries(
            localConversationSummaries: localConversationSummaries,
            serverRooms: visibleServerRooms
        )
        viewState.rooms = listEntries.map(makeRoomRow)
        viewState.hasMoreRooms = serverRooms.count > visibleServerRoomCount
        viewState.nextRoomPage = viewState.hasMoreRooms ? visibleServerRoomCount / ChatRoomListPaginationPolicy.defaultPageSize + 1 : nil
        viewState.messages = []
        viewState.selectedRoomID = nil
        resetSearchState()
        currentContext = nil
        isNearBottom = true
        activeChatRoomTracker.activeRoomId = nil
        viewState.showsNewMessageIndicator = false
        viewState.newMessageCount = 0
        viewState.emptyTitle = viewState.rooms.isEmpty ? "아직 채팅방이 없어요" : nil
        viewState.emptyMessage = viewState.rooms.isEmpty ? "상대방과 대화를 시작하면 여기에 표시돼요." : nil
        viewState.primaryActionTitle = viewState.rooms.isEmpty ? "다시 불러오기" : nil
        viewState.requiresAuthentication = false
        applyRoomListSearch()
    }

    private func applyMessages() {
        let countBefore = messages.count
        let roomScopeKey = viewState.selectedRoomID.map { currentScope(roomID: $0).roomScopeKey }
        messages = ChatMessageMergePolicy.deduplicated(
            messages,
            currentUserID: interactor.currentUserID,
            roomScopeKey: roomScopeKey
        )
#if DEBUG
        if ChatDebugOptions.isMergeLoggingEnabled, countBefore != messages.count {
            Logger.shared.debug("[ChatMerge] result countBefore=\(countBefore) countAfter=\(messages.count)")
        }
#endif
        viewState.rooms = []
        viewState.messages = makeMessageRows(messages)
        refreshSearchResultsForCurrentMessages()
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
            viewState.isInitialLoading = viewState.mode == .roomList
        }
    }

    private func clearLoading() {
        viewState.isLoading = false
        viewState.isInitialLoading = false
        viewState.isRefreshing = false
        viewState.isLoadingNextPage = false
    }

    private func makeRoomRow(_ entry: ChatListEntry) -> ChatRoomRowViewState {
        switch entry {
        case .storeScoped(let summary):
            return ChatRoomRowViewState(
                id: summary.id,
                title: summary.storeName,
                subtitle: summary.lastLocalMessage?.content.nilIfEmpty ?? "아직 대화가 없어요",
                timeText: relativeTime(from: summary.lastLocalMessage?.createdAt ?? summary.updatedAt),
                avatarPath: nil,
                section: .storeInquiry
            )
        case .server(let room):
            let participant = displayParticipant(for: room)
            let context = interactor.makeContext(for: room, entryPoint: .chatList)
            return ChatRoomRowViewState(
                id: "server:\(room.id)",
                title: context.displayTitle,
                subtitle: room.lastMessage?.content.nilIfEmpty ?? "일반 문의 대화를 시작해 보세요.",
                timeText: relativeTime(from: room.lastMessage?.createdAt ?? room.updatedAt),
                avatarPath: participant?.profileImagePath,
                section: .general
            )
        }
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
        let isSelected = viewState.selectedSearchResult?.messageID == message.renderID
        return ChatMessageRowViewState(
            id: message.renderID,
            serverChatID: message.effectiveServerChatID,
            localTemporaryID: message.effectiveLocalTemporaryID,
            clientMessageID: message.clientMessageID,
            dateText: dateText,
            content: message.content,
            searchMatchRanges: searchMatchRanges(for: message),
            filePaths: message.filePaths,
            timeText: message.createdAt.map { timeFormatter.string(from: $0) } ?? "",
            senderName: message.sender.nick,
            isMine: message.sender.id == interactor.currentUserID,
            sendStatus: message.sendStatus,
            isSelectedSearchMatch: isSelected
        )
    }

    private func roomTitle(_ room: ChatRoom) -> String {
        interactor.makeContext(for: room, entryPoint: .chatList).displayTitle
    }

    private func activateSearch() {
        guard viewState.mode == .roomDetail else { return }
        viewState.isSearchActive = true
        viewState.messageSearch.isSearchActive = true
        viewState.searchScope = .loadedMessagesOnly
        viewState.messageSearch.searchScope = .loadedMessagesOnly
        viewState.searchMayHaveOlderUnloadedMessages = true
        viewState.messageSearch.mayHaveOlderUnloadedMessages = true
        refreshSearchResultsForCurrentMessages()
#if DEBUG
        Logger(category: "ChatSearch").debug("[ChatSearch] activated roomId=\(viewState.selectedRoomID ?? "-")")
        Logger(category: "ChatSearch").debug("[ChatSearch] scope=loadedMessages reason=noDocumentedServerSearchEndpoint")
#endif
    }

    private func deactivateSearch() {
        searchTask?.cancel()
        searchTask = nil
        resetSearchState()
        applyMessages()
#if DEBUG
        Logger(category: "ChatSearch").debug("[ChatSearch] closed reason=cancel")
#endif
    }

    private func updateSearchQuery(_ query: String) {
        guard viewState.isSearchActive else { return }
        viewState.searchQuery = query
        viewState.messageSearch.query = query
        viewState.isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        viewState.messageSearch.isSearching = viewState.isSearching
        searchTask?.cancel()
        searchTask = nil
        applySearchResults(
            ChatSearchEngine.search(messages: messages, query: query),
            reason: "queryChanged"
        )
#if DEBUG
        Logger(category: "ChatSearch").debug("[ChatSearch] queryChanged length=\(query.count) matchCount=\(viewState.searchResults.count)")
#endif
    }

    private func refreshSearchResultsForCurrentMessages() {
        guard viewState.isSearchActive else { return }
        let results = ChatSearchEngine.search(messages: messages, query: viewState.searchQuery)
        applySearchResults(results, reason: "messagesChanged")
    }

    private func applySearchResults(_ results: [ChatSearchResult], reason: String) {
        let previousID = viewState.selectedSearchResult?.id
        viewState.searchResults = results.map {
            ChatSearchResultViewState(
                id: $0.id,
                messageID: $0.messageID,
                preview: $0.preview,
                matchRanges: $0.matchRanges,
                createdAt: $0.createdAt,
                messageIndex: $0.messageIndex
            )
        }
        viewState.messageSearch.matches = viewState.searchResults
        let trimmedQuery = viewState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedIndex: Int?
        if trimmedQuery.isEmpty || viewState.searchResults.isEmpty {
            selectedIndex = nil
        } else if let previousID,
                  let preservedIndex = viewState.searchResults.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = preservedIndex
        } else {
            selectedIndex = 0
        }
        viewState.selectedSearchResultIndex = selectedIndex
        viewState.messageSearch.selectedMatchIndex = viewState.selectedSearchResultIndex
        viewState.isSearching = false
        viewState.messageSearch.isSearching = false
        viewState.messages = makeMessageRows(messages)
        if let selectedIndex {
            let target = viewState.searchResults[selectedIndex].messageID
            viewState.messageSearch.scrollTargetChatId = target
            enqueueScroll(target: .message(id: target), reason: "search.\(reason)", animated: true)
#if DEBUG
            if previousID == nil || reason == "queryChanged" {
                Logger(category: "ChatSearch").debug("[ChatSearch] autoFocus policy=firstRenderingOrder index=\(selectedIndex) chatId=\(target)")
            }
#endif
        } else {
            viewState.messageSearch.scrollTargetChatId = nil
        }
#if DEBUG
        Logger(category: "ChatSearch").debug("[ChatSearch] queryChanged length=\(viewState.searchQuery.count) matchCount=\(results.count)")
#endif
    }

    private func selectSearchResult(offset: Int) {
        guard !viewState.searchResults.isEmpty else { return }
        let current = viewState.selectedSearchResultIndex ?? 0
        let next = (current + offset + viewState.searchResults.count) % viewState.searchResults.count
        viewState.selectedSearchResultIndex = next
        viewState.messageSearch.selectedMatchIndex = next
        viewState.messages = makeMessageRows(messages)
        viewState.messageSearch.scrollTargetChatId = viewState.searchResults[next].messageID
        enqueueScroll(target: .message(id: viewState.searchResults[next].messageID), reason: "searchNavigation", animated: true)
#if DEBUG
        Logger(category: "ChatSearch").debug("[ChatSearch] selected index=\(next) chatId=\(viewState.searchResults[next].messageID) wrap=true")
#endif
    }

    private func selectSearchResult(id: String) {
        guard let index = viewState.searchResults.firstIndex(where: { $0.id == id }) else { return }
        viewState.selectedSearchResultIndex = index
        viewState.messageSearch.selectedMatchIndex = index
        viewState.messages = makeMessageRows(messages)
        viewState.messageSearch.scrollTargetChatId = viewState.searchResults[index].messageID
        enqueueScroll(target: .message(id: viewState.searchResults[index].messageID), reason: "searchResult", animated: true)
#if DEBUG
        Logger(category: "ChatSearch").debug("[ChatSearch] selected index=\(index) chatId=\(viewState.searchResults[index].messageID)")
#endif
    }

    private func searchMatchRanges(for message: ChatMessage) -> [NSRange] {
        guard viewState.isSearchActive,
              !viewState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        if let result = viewState.searchResults.first(where: { $0.messageID == message.renderID }) {
            return result.matchRanges
        }
        return ChatSearchEngine.matchRanges(in: message.content, query: viewState.searchQuery)
    }

    private func resetSearchState() {
        searchTask?.cancel()
        searchTask = nil
        viewState.isSearchActive = false
        viewState.searchQuery = ""
        viewState.searchResults = []
        viewState.selectedSearchResultIndex = nil
        viewState.isSearching = false
        viewState.searchScope = .loadedMessagesOnly
        viewState.searchMayHaveOlderUnloadedMessages = true
        viewState.messageSearch = ChatMessageSearchState()
    }

    private func activateRoomListSearch() {
        guard viewState.mode == .roomList else { return }
        guard !viewState.roomListSearch.isActive else { return }
        viewState.roomListSearch.isActive = true
        applyRoomListSearch()
#if DEBUG
        Logger(category: "ChatRoomSearch").debug("[ChatRoomSearch] activated")
#endif
    }

    private func cancelRoomListSearch() {
        viewState.roomListSearch = ChatRoomSearchState(
            isActive: false,
            query: "",
            resultRoomIds: [],
            isLoading: false,
            emptyReason: nil,
            hasCompletedInitialLoad: viewState.roomListSearch.hasCompletedInitialLoad
        )
        applyRoomListSearch()
#if DEBUG
        Logger(category: "ChatRoomSearch").debug("[ChatRoomSearch] closed reason=cancel")
#endif
    }

    private func updateRoomListSearchQuery(_ query: String) {
        if !viewState.roomListSearch.isActive {
            activateRoomListSearch()
        }
        viewState.roomListSearchQuery = query
        applyRoomListSearch()
#if DEBUG
        Logger(category: "ChatRoomSearch").debug("[ChatRoomSearch] queryChanged length=\(query.trimmingCharacters(in: .whitespacesAndNewlines).count) resultCount=\(viewState.roomListSearch.resultRoomIds.count) source=roomsAndLastChat")
#endif
    }

    private func applyRoomListSearch() {
        let rows = listEntries.map(makeRoomRow)
        let query = viewState.roomListSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            viewState.rooms = rows
            viewState.roomListSearch.resultRoomIds = rows.map(\.id)
            viewState.roomListSearch.emptyReason = rows.isEmpty ? .noRooms : nil
            viewState.emptyTitle = rows.isEmpty ? "아직 채팅방이 없어요" : nil
            viewState.emptyMessage = rows.isEmpty ? "상대방과 대화를 시작하면 여기에 표시돼요." : nil
            viewState.primaryActionTitle = rows.isEmpty ? "다시 불러오기" : nil
            return
        }
        let filtered = rows.compactMap { row -> ChatRoomRowViewState? in
            let titleRanges = ChatSearchEngine.matchRanges(in: row.title, query: query)
            let subtitleRanges = ChatSearchEngine.matchRanges(in: row.subtitle, query: query)
            guard !titleRanges.isEmpty || !subtitleRanges.isEmpty else { return nil }
            return ChatRoomRowViewState(
                id: row.id,
                title: row.title,
                subtitle: row.subtitle,
                timeText: row.timeText,
                avatarPath: row.avatarPath,
                section: row.section,
                titleMatchRanges: titleRanges,
                subtitleMatchRanges: subtitleRanges,
                searchSnippet: row.searchSnippet
            )
        }
        viewState.rooms = filtered
        viewState.roomListSearch.resultRoomIds = filtered.map(\.id)
        viewState.roomListSearch.emptyReason = filtered.isEmpty ? .noMatches : nil
        let canShowSearchEmpty = viewState.roomListSearch.hasCompletedInitialLoad && filtered.isEmpty
        viewState.emptyTitle = canShowSearchEmpty ? "검색 결과가 없어요" : nil
        viewState.emptyMessage = canShowSearchEmpty ? "채팅방 이름이나 마지막 메시지를 다시 확인해 주세요." : nil
        viewState.primaryActionTitle = filtered.isEmpty ? "다시 불러오기" : nil
    }

    private func loadNextRoomPageIfNeeded() {
        guard viewState.mode == .roomList,
              viewState.hasMoreRooms,
              !viewState.isLoadingNextPage,
              !viewState.isInitialLoading,
              !viewState.isRefreshing else {
            return
        }
        viewState.isLoadingNextPage = true
        let before = visibleServerRoomCount
        let limit = ChatRoomListPaginationPolicy.clampedPageSize()
        visibleServerRoomCount = min(serverRooms.count, visibleServerRoomCount + limit)
#if DEBUG
        Logger(category: "ChatRoomList").debug("[ChatRoomList] loadNextPage limit=\(limit) cursor/page=local:\(before)")
        Logger(category: "ChatRoomList").debug("[ChatRoomList] merge before=\(before) incoming=\(visibleServerRoomCount - before) after=\(visibleServerRoomCount) deduped=0")
#endif
        applyRooms()
        viewState.isLoadingNextPage = false
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
                self.handleIncomingMessageNotification(message)
                if self.viewState.mode == .roomList {
                    Task {
                        await self.refreshLocalConversationSummariesForVisibleList()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func updateRoomList(with message: ChatMessage) {
        guard let index = serverRooms.firstIndex(where: { $0.id == message.roomID }) else {
            return
        }
        serverRooms[index] = serverRooms[index].updating(lastMessage: message)
        serverRooms = deduplicatedRooms(serverRooms)
    }

    private func applyContext(_ context: ChatRoomContext) {
        currentContext = context
        transitionLifecycle(to: .active(roomID: context.roomID), reason: "contextApplied")
        activeChatRoomTracker.activeRoomId = context.roomID
        viewState.title = context.displayTitle
        Logger.shared.debug("[ChatRoute] entered source=\(context.entryPoint.logValue) roomId=\(context.roomID)")
        Logger.shared.debug("[ChatRoomState] roomId=\(context.roomID) metadataLoaded=\(context.storeName != nil || context.opponentID != nil) composerEnabled=\(viewState.selectedRoomID != nil)")
        Logger.shared.debug(
            "[ChatNavigation] source=\(context.entryPoint.logValue) roomId=\(context.roomID) storeId=\(context.storeID ?? "-") opponentId=\(context.opponentID ?? "-") title=\(context.displayTitle)"
        )
        Logger.shared.debug(
            "[ChatRouteContext] hydrated roomId=\(context.roomID) storeId=\(context.storeID ?? "-") opponentId=\(context.opponentID ?? "-") title=\(context.displayTitle)"
        )
        Logger.shared.debug(
            "[ChatRoomContext] resolvedTitle=\(context.displayTitle) roomId=\(context.roomID) storeId=\(context.storeID ?? "-") storeName=\(context.storeName ?? "-") opponentId=\(context.opponentID ?? "-") metadataLoaded=\(context.storeName != nil || context.opponentID != nil) canUseStoreScopedTitle=\(context.canUseStoreScopedTitle)"
        )
        if context.hasRoomIDCollision {
            Logger.shared.info(
                "[ChatRoomContext] collision active localCacheKey=\(context.localCacheScope.localCacheKey) roomId=\(context.roomID) currentStoreId=\(context.storeID ?? "-") mappedStoreIds=\(context.collidingStoreIDs.joined(separator: ","))"
            )
        }
    }

    private func handleIncomingMessageNotification(_ message: ChatMessage) {
        guard message.sender.id != interactor.currentUserID else { return }
        notificationService.handleChatMessageReceived(
            roomId: message.roomID,
            storeId: currentContext?.storeID,
            title: currentContext?.displayTitle,
            messageId: message.effectiveServerChatID,
            senderId: message.sender.id,
            preview: message.content
        )
    }

    private func enqueueInitialScroll() {
        let action = ChatScrollPolicy.action(for: .initialLoad(targetMessageId: nil))
        Logger.shared.debug("[ChatScroll] initialScroll reason=deepLink target=latest")
        applyScrollActionResult(action, localTemporaryId: nil)
    }

    private func applyScrollPolicyForReceivedMessage(_ message: ChatMessage) {
        let senderIsCurrentUser = message.sender.id == interactor.currentUserID
        if senderIsCurrentUser {
            applyScrollAction(.echoReplace(localTemporaryId: message.effectiveLocalTemporaryID), localTemporaryId: message.effectiveLocalTemporaryID)
            return
        }

        let action = ChatScrollPolicy.action(for: .messageReceived(senderIsCurrentUser: false, isNearBottom: isNearBottom))
        Logger.shared.debug("[ChatScroll] messageReceived sender=other isNearBottom=\(isNearBottom) action=\(action.logValue)")
        applyScrollActionResult(action, localTemporaryId: nil)
    }

    private func applyScrollAction(_ input: ChatScrollInput, localTemporaryId: String?) {
        let action = ChatScrollPolicy.action(for: input)
        switch input {
        case .optimisticAppend:
            Logger.shared.debug("[ChatScroll] messageAppended sender=self action=scrollToBottom reason=optimistic")
        case .echoReplace:
            Logger.shared.debug("[ChatScroll] echoReplace action=keepPosition localTemporaryId=\(localTemporaryId ?? "-")")
        case .paginationPrepend:
            Logger.shared.debug("[ChatScroll] paginationPrepend action=preservePosition")
        case .initialLoad, .messageReceived:
            break
        }
        applyScrollActionResult(action, localTemporaryId: localTemporaryId)
    }

    private func applyScrollActionResult(_ action: ChatScrollActionResult, localTemporaryId: String?) {
        switch action {
        case .scrollToBottom(let reason):
#if DEBUG
            DebugLogDeduplicator.shared.printWhenChanged(
                key: "ChatAutoScroll.presenter",
                value: "execute|\(reason)|\(isNearBottom)",
                logger: Logger(category: "ChatAutoScroll"),
                message: "[ChatAutoScroll] action=execute reason=\(reason) nearBottom=\(isNearBottom) userInteracting=false"
            )
#endif
            enqueueScroll(target: .bottom, reason: reason, animated: true)
        case .scrollToMessage(let id, let reason):
            enqueueScroll(target: .message(id: id), reason: reason, animated: true)
        case .showNewMessageIndicator:
            viewState.newMessageCount += 1
            viewState.showsNewMessageIndicator = true
#if DEBUG
            DebugLogDeduplicator.shared.printWhenChanged(
                key: "ChatAutoScroll.presenter",
                value: "skip|newMessageIndicator|\(isNearBottom)",
                logger: Logger(category: "ChatAutoScroll"),
                message: "[ChatAutoScroll] action=skip reason=userAwayFromBottom nearBottom=\(isNearBottom) userInteracting=true"
            )
#endif
            Logger.shared.debug("[ChatScroll] messageReceived sender=other isNearBottom=false action=showNewMessageIndicator")
        case .keepPosition:
            _ = localTemporaryId
#if DEBUG
            DebugLogDeduplicator.shared.printWhenChanged(
                key: "ChatAutoScroll.presenter",
                value: "skip|echoReplace|\(isNearBottom)",
                logger: Logger(category: "ChatAutoScroll"),
                message: "[ChatAutoScroll] action=skip reason=echoReplace nearBottom=\(isNearBottom) userInteracting=false"
            )
#endif
        case .preservePosition:
#if DEBUG
            DebugLogDeduplicator.shared.printWhenChanged(
                key: "ChatAutoScroll.presenter",
                value: "skip|preservePosition|\(isNearBottom)",
                logger: Logger(category: "ChatAutoScroll"),
                message: "[ChatAutoScroll] action=skip reason=preservePosition nearBottom=\(isNearBottom) userInteracting=true"
            )
#endif
            break
        }
    }

    private func enqueueScroll(target: ChatScrollTarget, reason: String, animated: Bool) {
        scrollCommandID += 1
        viewState.scrollCommand = ChatScrollCommand(id: scrollCommandID, target: target, reason: reason, animated: animated)
        Logger.shared.debug("[ChatScroll] enqueue target=\(target.logValue) reason=\(reason)")
    }

    private func currentScope(roomID: String) -> ChatRoomScope {
        if let currentContext, currentContext.roomID == roomID {
            return currentContext.localCacheScope
        }
        return ChatRoomScope(roomID: roomID, storeID: nil, opponentID: nil)
    }

    private func canOpenRoom(_ roomID: String) -> Bool {
        if case .leaving(let leavingRoomID) = lifecycle, leavingRoomID == roomID {
            Logger.shared.debug("[ChatNavigation] duplicate open blocked reason=leaving roomId=\(roomID)")
            return false
        }
        if case .entering(let enteringRoomID) = lifecycle, enteringRoomID == roomID {
            Logger.shared.debug("[ChatNavigation] duplicate open blocked reason=entering roomId=\(roomID)")
            return false
        }
        return true
    }

    private func isCurrentRoomLifecycle(_ roomID: String) -> Bool {
        lifecycle == .entering(roomID: roomID) || lifecycle == .active(roomID: roomID)
    }

    private func transitionLifecycle(to newState: ChatRoomLifecycleState, reason: String) {
        let oldState = lifecycle
        guard oldState != newState else { return }
        guard isValidLifecycleTransition(from: oldState, to: newState) else {
            Logger.shared.debug("[ChatLifecycle] invalidTransition from=\(oldState.logValue) to=\(newState.logValue) ignored reason=\(reason)")
            return
        }
        lifecycle = newState
        if let roomID = newState.roomID ?? oldState.roomID {
            Logger.shared.debug("[ChatLifecycle] transition from=\(oldState.logValue) roomId=\(roomID) to=\(newState.logValue) reason=\(reason)")
        } else {
            Logger.shared.debug("[ChatLifecycle] transition from=\(oldState.logValue) roomId=nil to=\(newState.logValue) reason=\(reason)")
        }
    }

    private func isValidLifecycleTransition(from oldState: ChatRoomLifecycleState, to newState: ChatRoomLifecycleState) -> Bool {
        switch (oldState, newState) {
        case (.idle, .entering),
             (.entering, .entering),
             (.entering, .active),
             (.entering, .idle),
             (.active, .leaving),
             (.leaving, .idle),
             (.idle, .idle):
            return true
        default:
            return false
        }
    }

    private func logStaleUpdateIgnored(source: String, roomID: String) {
        Logger.shared.debug("[ChatLifecycle] stale update ignored source=\(source) roomId=\(roomID)")
    }

    private func cancelRoomTasks(reason: String) {
        let hadSearchTask = searchTask != nil
        searchTask?.cancel()
        searchTask = nil
        Logger.shared.debug("[ChatViewModel] cancelled room tasks count=\(hadSearchTask ? 1 : 0) reason=\(reason)")
    }

    private func normalizedRouteRoomID(from rowID: String) -> String {
        rowID.hasPrefix("server:") ? String(rowID.dropFirst("server:".count)) : rowID
    }

    private var debugRouteRoomID: String {
        if let selectedRoomID = viewState.selectedRoomID {
            return selectedRoomID
        }
        if case .room(let roomID, _, _, _, _, _) = interactor.target {
            return roomID
        }
        return "-"
    }

    private var debugRouteSource: String {
        if let currentContext {
            return currentContext.entryPoint.logValue
        }
        if case .room(_, _, _, let source, _, _) = interactor.target {
            return source.logValue
        }
        return interactor.target == nil ? "chatList" : "unknown"
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

    private func makeListEntries(
        localConversationSummaries: [ChatLocalConversationSummary],
        serverRooms: [ChatRoom]
    ) -> [ChatListEntry] {
        let storeScopedEntries = localConversationSummaries.map(ChatListEntry.storeScoped)
        let serverEntries = serverRooms.map(ChatListEntry.server)
#if DEBUG
        if ChatDebugOptions.isChatListMergeLoggingEnabled {
            DebugLogDeduplicator.shared.printWhenChanged(
                key: "ChatList.merge",
                value: "\(storeScopedEntries.count)|\(serverEntries.count)|sectioned",
                message: "[ChatList] merge storeScopedCount=\(storeScopedEntries.count) serverRoomCount=\(serverEntries.count) policy=sectioned"
            )
        }
#endif
        return storeScopedEntries + serverEntries
    }

    private func refreshLocalConversationSummariesForVisibleList() async {
        localConversationSummaries = (try? await interactor.loadLocalConversationSummaries()) ?? localConversationSummaries
        applyRooms()
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

    private func uploadErrorMessage(from error: Error) -> String? {
        if let localizedError = error as? LocalizedError,
           let message = localizedError.errorDescription,
           !message.isEmpty {
            return message
        }
        return transientErrorMessage(from: error) ?? "파일 업로드에 실패했어요. 다시 시도해 주세요."
    }
}

private enum ChatListEntry: Equatable, Identifiable {
    case storeScoped(ChatLocalConversationSummary)
    case server(ChatRoom)

    var id: String {
        switch self {
        case .storeScoped(let summary):
            return summary.id
        case .server(let room):
            return "server:\(room.id)"
        }
    }
}

private enum ChatRoomLifecycleState: Equatable {
    case idle
    case entering(roomID: String)
    case active(roomID: String)
    case leaving(roomID: String)

    var roomID: String? {
        switch self {
        case .idle:
            return nil
        case .entering(let roomID), .active(let roomID), .leaving(let roomID):
            return roomID
        }
    }

    var logValue: String {
        switch self {
        case .idle:
            return "idle"
        case .entering:
            return "entering"
        case .active:
            return "active"
        case .leaving:
            return "leaving"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ChatRoomEntryPoint {
    var logValue: String {
        switch self {
        case .storeDetail:
            return "storeDetail"
        case .storeScopedChatList:
            return "storeScopedChatList"
        case .chatList:
            return "chatList"
        case .userProfile:
            return "profile"
        case .remoteFCM:
            return "remoteFCM"
        case .localNotification:
            return "localNotification"
        case .deepLink:
            return "deepLink"
        case .orderDetail:
            return "orderDetail"
        case .unknown:
            return "unknown"
        }
    }
}
