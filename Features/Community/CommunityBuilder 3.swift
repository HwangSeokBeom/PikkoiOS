import Foundation

@MainActor
struct CommunityBuilder {
    func build() -> CommunityRootView {
        let router = CommunityRouter()
        let interactor = CommunityInteractor()
        let presenter = CommunityPresenter(interactor: interactor, router: router)
        return CommunityRootView(presenter: presenter)
    }
}
