import Foundation

@MainActor
struct ChatBuilder {
    private let storeID: String?
    private let opponentID: String?
    private let chatRepository: ChatRepository
    private let storeRepository: StoreRepository
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading

    init(
        storeID: String? = nil,
        opponentID: String? = nil,
        chatRepository: ChatRepository,
        storeRepository: StoreRepository,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading
    ) {
        self.storeID = storeID
        self.opponentID = opponentID
        self.chatRepository = chatRepository
        self.storeRepository = storeRepository
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
    }

    func build() -> ChatRootView {
        let router = ChatRouter()
        let interactor = ChatInteractor(
            storeID: storeID,
            opponentID: opponentID,
            chatRepository: chatRepository,
            storeRepository: storeRepository,
            sessionStore: sessionStore
        )
        let presenter = ChatPresenter(interactor: interactor, router: router)
        return ChatRootView(presenter: presenter, imageLoader: imageLoader)
    }
}
