import Foundation

@MainActor
struct StoreDetailBuilder {
    func build() -> StoreDetailRootView {
        let router = StoreDetailRouter()
        let interactor = StoreDetailInteractor()
        let presenter = StoreDetailPresenter(interactor: interactor, router: router)
        return StoreDetailRootView(presenter: presenter)
    }
}
