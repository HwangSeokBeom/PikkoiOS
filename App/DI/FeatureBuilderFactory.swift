import SwiftUI

@MainActor
struct FeatureBuilderFactory {
    private let container: AppDIContainer
    private let appState: AppState

    init(container: AppDIContainer, appState: AppState) {
        self.container = container
        self.appState = appState
    }

    func makeAuthView() -> AuthRootView {
        AuthBuilder(
            authRepository: container.authRepository,
            sessionStore: appState.sessionStore
        ).build()
    }

    func makeHomeView() -> HomeRootView {
        HomeBuilder(
            storeRepository: container.storeRepository,
            bannerRepository: container.bannerRepository,
            locationService: container.locationService,
            reverseGeocoder: container.reverseGeocoder,
            imageLoader: container.authorizedImageLoader
        ).build()
    }

    func makeStoreDetailView() -> StoreDetailRootView {
        StoreDetailBuilder().build()
    }

    func makeCartView() -> CartRootView {
        CartBuilder(cartStore: appState.cartStore).build()
    }

    func makeCheckoutView() -> CheckoutRootView {
        CheckoutBuilder().build()
    }

    func makeOrderView() -> OrderRootView {
        OrderBuilder().build()
    }

    func makeProfileView() -> ProfileRootView {
        ProfileBuilder(sessionStore: appState.sessionStore).build()
    }

    func makeCommunityView() -> CommunityRootView {
        CommunityBuilder().build()
    }

    func makeChatView() -> ChatRootView {
        ChatBuilder().build()
    }
}
