import Foundation

@MainActor
struct ChatBuilder {
    private let storeID: String?

    init(storeID: String? = nil) {
        self.storeID = storeID
    }

    func build() -> ChatRootView {
        let router = ChatRouter()
        let interactor = ChatInteractor(storeID: storeID)
        let presenter = ChatPresenter(interactor: interactor, router: router)
        return ChatRootView(presenter: presenter)
    }
}
