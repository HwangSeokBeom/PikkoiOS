import SwiftUI

@MainActor
struct CommunityComposerBuilder {
    private let mode: CommunityComposerMode
    private let initialDraft: CommunityComposerInitialDraft?
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol

    init(
        mode: CommunityComposerMode = .create,
        initialDraft: CommunityComposerInitialDraft? = nil,
        communityRepository: CommunityRepository,
        locationService: any LocationServiceProtocol
    ) {
        self.mode = mode
        self.initialDraft = initialDraft
        self.communityRepository = communityRepository
        self.locationService = locationService
    }

    func build(onSubmittedPost: @escaping (String) -> Void = { _ in }) -> CommunityComposerRootView {
        let router = CommunityComposerRouter()
        let interactor = CommunityComposerInteractor(
            mode: mode,
            initialDraft: initialDraft.map(CommunityComposerDraft.init(routeDraft:)),
            communityRepository: communityRepository,
            locationService: locationService
        )
        let presenter = CommunityComposerPresenter(
            interactor: interactor,
            router: router
        )

        return CommunityComposerRootView(
            presenter: presenter,
            router: router,
            onSubmittedPost: onSubmittedPost
        )
    }
}
