import Foundation

@MainActor
struct ChatBuilder {
    private let target: ChatTarget?
    private let chatRepository: ChatRepository
    private let localDataSource: any ChatLocalDataSourceProtocol
    private let makeRealtimeService: @MainActor () -> any ChatRealtimeServiceProtocol
    private let storeRepository: StoreRepository
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading

    init(
        target: ChatTarget? = nil,
        chatRepository: ChatRepository,
        localDataSource: any ChatLocalDataSourceProtocol,
        makeRealtimeService: @escaping @MainActor () -> any ChatRealtimeServiceProtocol,
        storeRepository: StoreRepository,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading
    ) {
        self.target = target
        self.chatRepository = chatRepository
        self.localDataSource = localDataSource
        self.makeRealtimeService = makeRealtimeService
        self.storeRepository = storeRepository
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
    }

    func build() -> ChatRootView {
        let router = ChatRouter()
        let interactor = ChatInteractor(
            target: target,
            chatRepository: chatRepository,
            localDataSource: localDataSource,
            realtimeService: makeRealtimeService(),
            storeRepository: storeRepository,
            sessionStore: sessionStore
        )
        let presenter = ChatPresenter(interactor: interactor, router: router)
        return ChatRootView(presenter: presenter, imageLoader: imageLoader)
    }
}
