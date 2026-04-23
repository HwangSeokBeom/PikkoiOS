import Foundation

@MainActor
struct ChatBuilder {
    func build() -> ChatRootView {
        let router = ChatRouter()
        let interactor = ChatInteractor()
        let presenter = ChatPresenter(interactor: interactor, router: router)
        return ChatRootView(presenter: presenter)
    }
}
