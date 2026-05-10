import XCTest
@testable import Pikko

@MainActor
final class ChatHardeningTests: XCTestCase {
    func testOptimisticMessageIsReplacedByHTTPResponseNotDuplicated() {
        let scope = ChatRoomScope(roomID: "room-1", storeID: "store-1", opponentID: "user-2")
        let optimistic = makeMessage(
            id: "local-1",
            localTemporaryID: "local-1",
            clientMessageID: "client-1",
            serverChatID: nil,
            roomID: "room-1",
            content: "hello",
            createdAt: date(1),
            senderID: "user-1",
            status: .sending
        )
        let http = makeMessage(
            id: "server-1",
            localTemporaryID: nil,
            clientMessageID: "client-1",
            serverChatID: "server-1",
            roomID: "room-1",
            content: "hello",
            createdAt: date(2),
            senderID: "user-1",
            status: .sent
        )

        let result = ChatMessageMergePolicy.merged(
            existing: [optimistic],
            incoming: http,
            currentUserID: "user-1",
            source: "http",
            roomScopeKey: scope.roomScopeKey
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.effectiveServerChatID, "server-1")
        XCTAssertEqual(result.first?.clientMessageID, "client-1")
        XCTAssertEqual(result.first?.effectiveLocalTemporaryID, "local-1")
        XCTAssertEqual(result.first?.sendStatus, .sent)
    }

    func testOptimisticMessageIsReplacedBySocketEchoNotDuplicated() {
        let optimistic = makeMessage(
            id: "local-1",
            localTemporaryID: "local-1",
            clientMessageID: "client-1",
            serverChatID: nil,
            content: "hello",
            createdAt: date(1),
            status: .sending
        )
        let socket = makeMessage(
            id: "server-1",
            clientMessageID: "client-1",
            serverChatID: "server-1",
            content: "hello",
            createdAt: date(2),
            status: .sent
        )

        let result = ChatMessageMergePolicy.merged(
            existing: [optimistic],
            incoming: socket,
            currentUserID: "user-1",
            source: "socket",
            roomScopeKey: "room:room-1|store:-|opponent:-"
        )

        XCTAssertEqual(result.map(\.effectiveServerChatID), ["server-1"])
    }

    func testHTTPResponseAndSocketEchoInEitherOrderProduceOneMessage() {
        let http = makeMessage(id: "server-1", clientMessageID: "client-1", serverChatID: "server-1", content: "hello", createdAt: date(2))
        let socket = makeMessage(id: "server-1", clientMessageID: "client-1", serverChatID: "server-1", content: "hello", createdAt: date(2))

        let httpThenSocket = ChatMessageMergePolicy.merged(
            existing: ChatMessageMergePolicy.merged(existing: [], incoming: http, currentUserID: "user-1", source: "http"),
            incoming: socket,
            currentUserID: "user-1",
            source: "socket"
        )
        let socketThenHTTP = ChatMessageMergePolicy.merged(
            existing: ChatMessageMergePolicy.merged(existing: [], incoming: socket, currentUserID: "user-1", source: "socket"),
            incoming: http,
            currentUserID: "user-1",
            source: "http"
        )

        XCTAssertEqual(httpThenSocket.count, 1)
        XCTAssertEqual(socketThenHTTP.count, 1)
    }

    func testRESTSyncContainingVisibleSocketMessageDoesNotDuplicateIt() {
        let socket = makeMessage(id: "server-1", serverChatID: "server-1", content: "hello", createdAt: date(2))
        let rest = makeMessage(id: "server-1", serverChatID: "server-1", content: "hello", createdAt: date(2))

        let result = ChatMessageMergePolicy.merged(
            existing: [socket],
            incoming: rest,
            currentUserID: "user-1",
            source: "rest"
        )

        XCTAssertEqual(result.count, 1)
    }

    func testRetryUsesSameClientMessageID() {
        let failed = makeMessage(
            id: "local-1",
            localTemporaryID: "local-1",
            clientMessageID: "client-1",
            serverChatID: nil,
            status: .failed
        )
        let retrying = failed.replacingIdentity(sendStatus: .retrying)

        XCTAssertEqual(retrying.clientMessageID, "client-1")
        XCTAssertEqual(retrying.effectiveLocalTemporaryID, "local-1")
    }

    func testTimeoutFollowedByRESTSyncRecoversPendingMessage() {
        let failed = makeMessage(
            id: "local-1",
            localTemporaryID: "local-1",
            clientMessageID: "client-1",
            serverChatID: nil,
            content: "hello",
            createdAt: date(1),
            status: .failed
        )
        let rest = makeMessage(
            id: "server-1",
            clientMessageID: "client-1",
            serverChatID: "server-1",
            content: "hello",
            createdAt: date(2),
            status: .sent
        )

        let result = ChatMessageMergePolicy.merged(
            existing: [failed],
            incoming: rest,
            currentUserID: "user-1",
            source: "rest"
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.effectiveServerChatID, "server-1")
        XCTAssertEqual(result.first?.sendStatus, .sent)
    }

    func testSameRoomIDDifferentStoreIDDoesNotMixLocalMessages() async throws {
        let localDataSource = CoreDataChatLocalDataSource(inMemory: true)
        let storeAScope = ChatRoomScope(roomID: "room-1", storeID: "store-A", opponentID: "owner")
        let storeBScope = ChatRoomScope(roomID: "room-1", storeID: "store-B", opponentID: "owner")

        try await localDataSource.upsert(
            messages: [makeMessage(id: "server-A", serverChatID: "server-A", content: "store A")],
            scope: storeAScope
        )
        try await localDataSource.upsert(
            messages: [makeMessage(id: "server-B", serverChatID: "server-B", content: "store B")],
            scope: storeBScope
        )

        let storeAMessages = try await localDataSource.fetchMessages(scope: storeAScope)
        let storeBMessages = try await localDataSource.fetchMessages(scope: storeBScope)

        XCTAssertEqual(storeAMessages.map(\.content), ["store A"])
        XCTAssertEqual(storeBMessages.map(\.content), ["store B"])
    }

    func testPaginationOverlapDoesNotDuplicateMessages() {
        let current = [
            makeMessage(id: "server-2", serverChatID: "server-2", content: "newer", createdAt: date(2))
        ]
        let olderPageOverlap = [
            makeMessage(id: "server-1", serverChatID: "server-1", content: "older", createdAt: date(1)),
            makeMessage(id: "server-2", serverChatID: "server-2", content: "newer", createdAt: date(2))
        ]

        let result = olderPageOverlap.reduce(current) { messages, incoming in
            ChatMessageMergePolicy.merged(
                existing: messages,
                incoming: incoming,
                currentUserID: "user-1",
                source: "pagination"
            )
        }

        XCTAssertEqual(result.map(\.effectiveServerChatID), ["server-1", "server-2"])
    }

    func testStaleRefetchCannotOverwriteNewerConfirmedMessageState() {
        let newer = makeMessage(
            id: "server-1",
            serverChatID: "server-1",
            content: "edited",
            createdAt: date(1),
            updatedAt: date(3)
        )
        let stale = makeMessage(
            id: "server-1",
            serverChatID: "server-1",
            content: "old",
            createdAt: date(1),
            updatedAt: date(2)
        )

        let result = ChatMessageMergePolicy.merged(
            existing: [newer],
            incoming: stale,
            currentUserID: "user-1",
            source: "rest"
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "edited")
    }

    func testSocketReconnectCanTriggerRESTBackfillHook() async throws {
        let realtime = ReconnectCapturingRealtimeService()
        let interactor = makeInteractor(realtimeService: realtime)
        let scope = ChatRoomScope(roomID: "room-1", storeID: nil, opponentID: nil)
        var didBackfill = false

        try await interactor.startRealtime(scope: scope) { _ in
        } onReconnect: {
            didBackfill = true
        }
        await realtime.triggerReconnect()

        XCTAssertTrue(didBackfill)
    }

    func testChatSearchFindsKoreanAndEnglishCaseInsensitively() {
        let messages = [
            makeMessage(id: "server-1", serverChatID: "server-1", content: "안녕하세요 픽코입니다", createdAt: date(1)),
            makeMessage(id: "server-2", serverChatID: "server-2", content: "Hello Pikko", createdAt: date(2))
        ]

        XCTAssertEqual(ChatSearchEngine.search(messages: messages, query: "픽코").map(\.messageID), ["server-1"])
        XCTAssertEqual(ChatSearchEngine.search(messages: messages, query: "pikko").map(\.messageID), ["server-2"])
    }

    func testChatSearchHighlightsMultipleOccurrencesInOneMessage() {
        let message = makeMessage(id: "server-1", serverChatID: "server-1", content: "Pikko pikko PIKKO")

        let result = ChatSearchEngine.search(messages: [message], query: "pikko")

        XCTAssertEqual(result.first?.matchRanges.count, 3)
    }

    func testChatSearchResultUsesClientIDForOptimisticMessageStability() {
        let optimistic = makeMessage(
            id: "local-1",
            localTemporaryID: "local-1",
            clientMessageID: "client-1",
            serverChatID: nil,
            content: "upload receipt",
            status: .sending
        )

        let result = ChatSearchEngine.search(messages: [optimistic], query: "receipt")

        XCTAssertEqual(result.first?.id, "client:client-1")
        XCTAssertEqual(result.first?.messageID, "local-1")
    }

    func testChatListSearchFiltersByNicknameAndLastMessageLocally() async {
        let rooms = [
            makeRoom(id: "room-1", opponentName: "민지", lastContent: "오늘 LATTE 가능해요"),
            makeRoom(id: "room-2", opponentName: "준호", lastContent: "내일 픽업할게요")
        ]
        let presenter = ChatPresenter(
            interactor: makeInteractor(chatRepository: StubChatRepository(rooms: rooms)),
            router: StubChatRouter()
        )

        await presenter.send(.onAppear(instanceID: "test", presentationKind: .internal))
        XCTAssertEqual(Set(presenter.viewState.rooms.map(\.title)), Set(["민지", "준호"]))

        await presenter.send(.roomListSearchQueryChanged("민지"))
        XCTAssertEqual(presenter.viewState.rooms.map(\.title), ["민지"])
        XCTAssertEqual(presenter.viewState.roomListSearchResultCount, 1)

        await presenter.send(.roomListSearchQueryChanged("latte"))
        XCTAssertEqual(presenter.viewState.rooms.map(\.title), ["민지"])
        XCTAssertEqual(presenter.viewState.roomListSearchResultCount, 1)
    }

    func testChatListSearchShowsNoResultAndClearsBackToRoomList() async {
        let rooms = [
            makeRoom(id: "room-1", opponentName: "민지", lastContent: "안녕하세요"),
            makeRoom(id: "room-2", opponentName: "Alex", lastContent: "Hello Pikko")
        ]
        let presenter = ChatPresenter(
            interactor: makeInteractor(chatRepository: StubChatRepository(rooms: rooms)),
            router: StubChatRouter()
        )

        await presenter.send(.onAppear(instanceID: "test", presentationKind: .internal))
        await presenter.send(.roomListSearchQueryChanged("없음"))

        XCTAssertTrue(presenter.viewState.rooms.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyTitle, "검색 결과가 없어요")
        XCTAssertEqual(presenter.viewState.roomListSearchResultCount, 0)

        await presenter.send(.roomListSearchQueryChanged(""))

        XCTAssertEqual(Set(presenter.viewState.rooms.map(\.title)), Set(["민지", "Alex"]))
        XCTAssertNil(presenter.viewState.emptyTitle)
        XCTAssertNil(presenter.viewState.roomListSearchResultCount)
    }

    func testChatListEmptyQueryReturnsFullListAndNoEmptySearchState() async {
        let rooms = [
            makeRoom(id: "room-1", opponentName: "민지", lastContent: "안녕하세요"),
            makeRoom(id: "room-2", opponentName: "Alex", lastContent: "Hello Pikko")
        ]
        let presenter = ChatPresenter(
            interactor: makeInteractor(chatRepository: StubChatRepository(rooms: rooms)),
            router: StubChatRouter()
        )

        await presenter.send(.onAppear(instanceID: "test", presentationKind: .internal))
        await presenter.send(.activateRoomListSearch)
        await presenter.send(.roomListSearchQueryChanged("   "))

        XCTAssertEqual(Set(presenter.viewState.rooms.map(\.title)), Set(["민지", "Alex"]))
        XCTAssertNil(presenter.viewState.roomListSearchResultCount)
        XCTAssertNil(presenter.viewState.emptyTitle)
    }

    func testChatListSearchReloadRefetchesRoomsAndReappliesQuery() async {
        let counter = ChatRepositoryCallCounter()
        let repository = StubChatRepository(
            rooms: [
                makeRoom(id: "room-1", opponentName: "민지", lastContent: "오늘 LATTE 가능해요"),
                makeRoom(id: "room-2", opponentName: "준호", lastContent: "내일 픽업할게요")
            ],
            callCounter: counter
        )
        let presenter = ChatPresenter(
            interactor: makeInteractor(chatRepository: repository),
            router: StubChatRouter()
        )

        await presenter.send(.onAppear(instanceID: "test", presentationKind: .internal))
        await presenter.send(.roomListSearchQueryChanged("latte"))
        await presenter.send(.refreshRequested)

        let fetchChatRoomsCount = await counter.fetchChatRoomsCount()
        let fetchMessagesCount = await counter.fetchMessagesCount()
        XCTAssertEqual(fetchChatRoomsCount, 2)
        XCTAssertEqual(presenter.viewState.rooms.map(\.title), ["민지"])
        XCTAssertEqual(presenter.viewState.roomListSearchResultCount, 1)
        XCTAssertEqual(fetchMessagesCount, 0)
    }

    func testMessageSearchOneResultSelectsScrollTargetAndHighlights() async {
        let presenter = await makeLoadedRoomPresenter(messages: [
            makeMessage(id: "server-1", serverChatID: "server-1", content: "hello", createdAt: date(1)),
            makeMessage(id: "server-2", serverChatID: "server-2", content: "Sd message", createdAt: date(2))
        ])

        await presenter.send(.searchTapped)
        await presenter.send(.searchQueryChanged("sd"))

        XCTAssertEqual(presenter.viewState.searchResults.count, 1)
        XCTAssertEqual(presenter.viewState.selectedSearchResultIndex, 0)
        XCTAssertEqual(presenter.viewState.messageSearch.scrollTargetChatId, "server-2")
        XCTAssertEqual(presenter.viewState.scrollCommand?.target, .message(id: "server-2"))
        XCTAssertEqual(presenter.viewState.messages.first(where: { $0.id == "server-2" })?.searchMatchRanges.count, 1)
        XCTAssertEqual(presenter.viewState.messages.first(where: { $0.id == "server-2" })?.isSelectedSearchMatch, true)
    }

    func testMessageSearchMultipleResultsNavigatesSequentially() async {
        let presenter = await makeLoadedRoomPresenter(messages: [
            makeMessage(id: "server-1", serverChatID: "server-1", content: "메시지 하나", createdAt: date(1)),
            makeMessage(id: "server-2", serverChatID: "server-2", content: "둘", createdAt: date(2)),
            makeMessage(id: "server-3", serverChatID: "server-3", content: "메시지 둘", createdAt: date(3))
        ])

        await presenter.send(.searchTapped)
        await presenter.send(.searchQueryChanged("메시지"))

        XCTAssertEqual(presenter.viewState.searchStatusText, "1 / 2")
        XCTAssertEqual(presenter.viewState.selectedSearchResult?.messageID, "server-1")

        await presenter.send(.nextSearchResultTapped)
        XCTAssertEqual(presenter.viewState.searchStatusText, "2 / 2")
        XCTAssertEqual(presenter.viewState.selectedSearchResult?.messageID, "server-3")

        await presenter.send(.previousSearchResultTapped)
        XCTAssertEqual(presenter.viewState.searchStatusText, "1 / 2")
        XCTAssertEqual(presenter.viewState.selectedSearchResult?.messageID, "server-1")
    }

    func testMessageSearchNoResultClearsSelectionAndScrollTarget() async {
        let presenter = await makeLoadedRoomPresenter(messages: [
            makeMessage(id: "server-1", serverChatID: "server-1", content: "hello", createdAt: date(1))
        ])

        await presenter.send(.searchTapped)
        await presenter.send(.searchQueryChanged("없음"))

        XCTAssertTrue(presenter.viewState.searchResults.isEmpty)
        XCTAssertNil(presenter.viewState.selectedSearchResultIndex)
        XCTAssertNil(presenter.viewState.messageSearch.scrollTargetChatId)
        XCTAssertEqual(presenter.viewState.searchStatusText, "검색 결과가 없어요.")
    }

    func testIncomingSocketMessageRecomputesSearchAndPreservesSelectedMatch() async {
        let realtime = ReconnectCapturingRealtimeService()
        let presenter = await makeLoadedRoomPresenter(
            messages: [
                makeMessage(id: "server-1", serverChatID: "server-1", content: "match one", createdAt: date(1)),
                makeMessage(id: "server-2", serverChatID: "server-2", content: "match two", createdAt: date(2))
            ],
            realtimeService: realtime
        )

        await presenter.send(.searchTapped)
        await presenter.send(.searchQueryChanged("match"))
        await presenter.send(.nextSearchResultTapped)
        XCTAssertEqual(presenter.viewState.selectedSearchResult?.messageID, "server-2")

        await realtime.triggerMessage(makeMessage(id: "server-3", serverChatID: "server-3", content: "match three", createdAt: date(3), senderID: "user-2"))

        XCTAssertEqual(presenter.viewState.searchResults.count, 3)
        XCTAssertEqual(presenter.viewState.selectedSearchResult?.messageID, "server-2")
    }

    func testSearchCancelClearsQueryHighlightsAndRestoresNormalChatUI() async {
        let presenter = await makeLoadedRoomPresenter(messages: [
            makeMessage(id: "server-1", serverChatID: "server-1", content: "hello", createdAt: date(1))
        ])

        await presenter.send(.searchTapped)
        await presenter.send(.searchQueryChanged("hello"))
        await presenter.send(.searchDismissed)

        XCTAssertFalse(presenter.viewState.isSearchActive)
        XCTAssertEqual(presenter.viewState.searchQuery, "")
        XCTAssertTrue(presenter.viewState.searchResults.isEmpty)
        XCTAssertEqual(presenter.viewState.messages.first?.searchMatchRanges, [])
        XCTAssertEqual(presenter.viewState.messages.first?.isSelectedSearchMatch, false)
    }

    func testChatUploadValidatorAcceptsUppercaseSupportedExtensions() throws {
        let files = [
            ChatUploadFile(data: Data("jpg".utf8), fileName: "a.JPG", mimeType: "image/jpeg", typeIdentifier: "public.jpeg"),
            ChatUploadFile(data: Data("pdf".utf8), fileName: "b.PDF", mimeType: "application/pdf", typeIdentifier: "com.adobe.pdf")
        ]

        XCTAssertNoThrow(try files.forEach { _ = try ChatUploadValidator.prepareFile($0) })
    }

    func testChatUploadValidatorRejectsUnsupportedExtension() {
        let file = ChatUploadFile(data: Data("zip".utf8), fileName: "a.zip", mimeType: "application/zip")

        XCTAssertThrowsError(try ChatUploadValidator.prepareFile(file)) { error in
            XCTAssertEqual(error as? ChatUploadValidationError, .unsupportedType(fileName: "a.zip"))
        }
    }

    func testChatUploadValidatorRejectsMoreThanFiveFiles() {
        XCTAssertThrowsError(try ChatUploadValidator.validateFileCount(incomingCount: 6)) { error in
            XCTAssertEqual(error as? ChatUploadValidationError, .tooManyFiles)
        }
    }

    func testChatUploadValidatorRejectsLargePDFWithoutCompression() {
        let file = ChatUploadFile(
            data: Data(repeating: 0x20, count: ChatUploadPolicy.maxFileSizeBytes + 1),
            fileName: "large.PDF",
            mimeType: "application/pdf",
            typeIdentifier: "com.adobe.pdf"
        )

        XCTAssertThrowsError(try ChatUploadValidator.prepareFile(file)) { error in
            XCTAssertEqual(error as? ChatUploadValidationError, .fileTooLarge(fileName: "large.PDF"))
        }
    }

    private func makeMessage(
        id: String = "server-1",
        localTemporaryID: String? = nil,
        clientMessageID: String? = nil,
        serverChatID: String? = "server-1",
        roomID: String = "room-1",
        content: String = "hello",
        createdAt: Date? = Date(timeIntervalSince1970: 1),
        updatedAt: Date? = nil,
        senderID: String = "user-1",
        status: ChatSendStatus = .sent
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            localTemporaryID: localTemporaryID,
            clientMessageID: clientMessageID,
            serverChatID: serverChatID,
            roomID: roomID,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sender: ChatParticipant(id: senderID, nick: senderID, profileImagePath: nil),
            filePaths: [],
            sendStatus: status
        )
    }

    private func makeRoom(id: String, opponentName: String, lastContent: String) -> ChatRoom {
        ChatRoom(
            id: id,
            createdAt: date(1),
            updatedAt: date(2),
            participants: [
                ChatParticipant(id: "user-1", nick: "나", profileImagePath: nil),
                ChatParticipant(id: "\(id)-opponent", nick: opponentName, profileImagePath: nil)
            ],
            lastMessage: makeMessage(
                id: "\(id)-message",
                serverChatID: "\(id)-message",
                roomID: id,
                content: lastContent,
                createdAt: date(2),
                senderID: "\(id)-opponent"
            ),
            storeID: nil,
            storeName: nil,
            opponentID: "\(id)-opponent",
            opponentName: opponentName,
            roomType: nil
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func makeInteractor(
        target: ChatTarget? = nil,
        chatRepository: StubChatRepository = StubChatRepository(),
        realtimeService: ChatRealtimeServiceProtocol = ReconnectCapturingRealtimeService()
    ) -> ChatInteractor {
        let sessionStore = SessionStore(
            tokenStore: StubChatTokenStore(),
            userDefaultsStore: UserDefaultsStore(userDefaults: UserDefaults(suiteName: "ChatHardeningTests.\(UUID().uuidString)")!)
        )
        sessionStore.apply(session: UserSession(
            userID: "user-1",
            email: "user@example.com",
            displayName: "User",
            profileImagePath: nil,
            accessToken: "access-token",
            refreshToken: "refresh-token"
        ))
        return ChatInteractor(
            target: target,
            chatRepository: chatRepository,
            localDataSource: CoreDataChatLocalDataSource(inMemory: true),
            realtimeService: realtimeService,
            storeRepository: StubChatStoreRepository(),
            sessionStore: sessionStore
        )
    }

    @MainActor
    private func makeLoadedRoomPresenter(
        messages: [ChatMessage],
        realtimeService: ChatRealtimeServiceProtocol = ReconnectCapturingRealtimeService()
    ) async -> ChatPresenter {
        let rooms = [makeRoom(id: "room-1", opponentName: "민지", lastContent: messages.last?.content ?? "")]
        let presenter = ChatPresenter(
            interactor: makeInteractor(
                chatRepository: StubChatRepository(rooms: rooms, messages: messages),
                realtimeService: realtimeService
            ),
            router: StubChatRouter()
        )
        await presenter.send(.onAppear(instanceID: "test", presentationKind: .internal))
        await presenter.send(.roomTapped("server:room-1"))
        return presenter
    }
}

@MainActor
private final class StubChatRouter: ChatRouting {
    func routeToPrimaryDestination() {}
}

private actor StubChatTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}

private struct StubChatRepository: ChatRepository {
    var rooms: [ChatRoom] = []
    var messages: [ChatMessage] = []
    var callCounter: ChatRepositoryCallCounter?

    func fetchChatRooms() async throws -> [ChatRoom] {
        await callCounter?.recordFetchChatRooms()
        return rooms
    }
    func createOrFetchChatRoom(mode: ChatRoomCreationMode) async throws -> ChatRoom {
        ChatRoom(
            id: "room-1",
            createdAt: nil,
            updatedAt: nil,
            participants: [],
            lastMessage: nil,
            storeID: nil,
            storeName: nil,
            opponentID: nil,
            opponentName: nil,
            roomType: nil
        )
    }
    func fetchMessages(roomID: String, next: String?) async throws -> [ChatMessage] {
        await callCounter?.recordFetchMessages()
        return messages
    }
    func sendMessage(roomID: String, content: String, files: [String], clientMessageID: String) async throws -> ChatMessage {
        ChatMessage(
            id: "server-1",
            clientMessageID: clientMessageID,
            serverChatID: "server-1",
            roomID: roomID,
            content: content,
            createdAt: Date(),
            updatedAt: nil,
            sender: ChatParticipant(id: "user-1", nick: "user-1", profileImagePath: nil),
            filePaths: files
        )
    }
    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> [String] { [] }
}

private actor ChatRepositoryCallCounter {
    private var roomFetches = 0
    private var messageFetches = 0

    func fetchChatRoomsCount() -> Int { roomFetches }
    func fetchMessagesCount() -> Int { messageFetches }

    func recordFetchChatRooms() {
        roomFetches += 1
    }

    func recordFetchMessages() {
        messageFetches += 1
    }
}

@MainActor
private final class ReconnectCapturingRealtimeService: ChatRealtimeServiceProtocol {
    private var onReconnect: (@MainActor () async -> Void)?
    private var onMessage: (@MainActor (ChatMessage) async -> Void)?

    func connect(
        roomID: String,
        currentUserID: String?,
        onMessage: @escaping @MainActor (ChatMessage) async -> Void,
        onReconnect: @escaping @MainActor () async -> Void
    ) async throws {
        self.onMessage = onMessage
        self.onReconnect = onReconnect
    }

    func disconnect() {}

    func triggerReconnect() async {
        await onReconnect?()
    }

    func triggerMessage(_ message: ChatMessage) async {
        await onMessage?(message)
    }
}

private struct StubChatStoreRepository: StoreRepository {
    func fetchStoreDetail(storeID: String) async throws -> StoreDetail {
        throw ChatFeatureError.unavailable(message: "stub")
    }

    func searchStores(name: String?) async throws -> [StoreSummary] { [] }

    func fetchNearbyStores(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreSortOrder
    ) async throws -> CursorPage<StoreSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func fetchPopularStores(category: String?) async throws -> [StoreSummary] { [] }

    func fetchPopularSearchTerms() async throws -> [String] { [] }

    func fetchLikedStores(category: String?, nextCursor: String?, limit: Int) async throws -> CursorPage<StoreSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool { isLiked }
}
