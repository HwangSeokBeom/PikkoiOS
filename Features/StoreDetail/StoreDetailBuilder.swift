import Foundation
import SwiftUI

@MainActor
struct StoreDetailBuilder {
    private let storeID: String
    private let storeRepository: StoreRepository
    private let reviewRepository: ReviewRepository
    private let orderRepository: OrderRepository
    private let cartStore: CartStore
    private let locationService: any LocationServiceProtocol
    private let mapLauncher: any MapLauncherProtocol
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: () -> AnyView
    private let makeCartView: (String) -> CartRootView
    private let makeChatView: (String) -> ChatRootView
    private let makeReviewComposerView: (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView

    init(
        storeID: String,
        storeRepository: StoreRepository,
        reviewRepository: ReviewRepository,
        orderRepository: OrderRepository,
        cartStore: CartStore,
        locationService: any LocationServiceProtocol,
        mapLauncher: any MapLauncherProtocol,
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping () -> AnyView,
        makeCartView: @escaping (String) -> CartRootView,
        makeChatView: @escaping (String) -> ChatRootView,
        makeReviewComposerView: @escaping (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView
    ) {
        self.storeID = storeID
        self.storeRepository = storeRepository
        self.reviewRepository = reviewRepository
        self.orderRepository = orderRepository
        self.cartStore = cartStore
        self.locationService = locationService
        self.mapLauncher = mapLauncher
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeCartView = makeCartView
        self.makeChatView = makeChatView
        self.makeReviewComposerView = makeReviewComposerView
    }

    func build() -> StoreDetailRootView {
        let router = StoreDetailRouter(mapLauncher: mapLauncher)
        let interactor = StoreDetailInteractor(
            storeID: storeID,
            storeRepository: storeRepository,
            reviewRepository: reviewRepository,
            orderRepository: orderRepository,
            locationService: locationService
        )
        let presenter = StoreDetailPresenter(
            interactor: interactor,
            router: router,
            cartStore: cartStore
        )
        return StoreDetailRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeAuthView: makeAuthView,
            makeCartView: makeCartView,
            makeChatView: makeChatView,
            makeReviewComposerView: makeReviewComposerView
        )
    }
}
