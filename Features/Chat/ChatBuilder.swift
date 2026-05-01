import Foundation

@MainActor
struct ChatBuilder {
    private let target: ChatTarget?
    private let chatRepository: ChatRepository
    private let localDataSource: any ChatLocalDataSourceProtocol
    private let makeRealtimeService: @MainActor () -> any ChatRealtimeServiceProtocol
    private let storeRepository: StoreRepository
    private let sessionStore: SessionStore
    private let notificationService: AppNotificationService
    private let activeChatRoomTracker: ActiveChatRoomTracking
    private let imageLoader: any AuthorizedImageLoading

    init(
        target: ChatTarget? = nil,
        chatRepository: ChatRepository,
        localDataSource: any ChatLocalDataSourceProtocol,
        makeRealtimeService: @escaping @MainActor () -> any ChatRealtimeServiceProtocol,
        storeRepository: StoreRepository,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        activeChatRoomTracker: ActiveChatRoomTracking = ActiveChatRoomTracker(),
        imageLoader: any AuthorizedImageLoading
    ) {
        self.target = target
        self.chatRepository = chatRepository
        self.localDataSource = localDataSource
        self.makeRealtimeService = makeRealtimeService
        self.storeRepository = storeRepository
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.activeChatRoomTracker = activeChatRoomTracker
        self.imageLoader = imageLoader
    }

    func build() -> ChatRootView {
        let router = ChatRouter()
        let interactor = ChatInteractor(
            target: target,
            chatRepository: chatRepository,
            localDataSource: localDataSource,
            realtimeService: LazyChatRealtimeService(factory: makeRealtimeService),
            storeRepository: storeRepository,
            sessionStore: sessionStore
        )
        let presenter = ChatPresenter(
            interactor: interactor,
            router: router,
            notificationService: notificationService,
            activeChatRoomTracker: activeChatRoomTracker
        )
        return ChatRootView(presenter: presenter, imageLoader: imageLoader)
    }
}

@MainActor
private final class LazyChatRealtimeService: ChatRealtimeServiceProtocol {
    private let factory: @MainActor () -> any ChatRealtimeServiceProtocol
    private var service: (any ChatRealtimeServiceProtocol)?

    init(factory: @escaping @MainActor () -> any ChatRealtimeServiceProtocol) {
        self.factory = factory
    }

    func connect(
        roomID: String,
        currentUserID: String?,
        onMessage: @escaping @MainActor (ChatMessage) async -> Void
    ) async throws {
        let service = resolvedService()
        try await service.connect(roomID: roomID, currentUserID: currentUserID, onMessage: onMessage)
    }

    func disconnect() {
        service?.disconnect()
    }

    private func resolvedService() -> any ChatRealtimeServiceProtocol {
        if let service {
            return service
        }
        let service = factory()
        self.service = service
        return service
    }
}
