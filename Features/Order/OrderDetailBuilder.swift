import SwiftUI

@MainActor
struct OrderDetailBuilder {
    private let orderID: String
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let mapper: OrderMapper
    private let makeAuthView: () -> AnyView
    private let makeStoreDetailView: (String) -> AnyView
    private let makeReviewComposerView: (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView

    init(
        orderID: String,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading,
        mapper: OrderMapper,
        makeAuthView: @escaping () -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView,
        makeReviewComposerView: @escaping (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView
    ) {
        self.orderID = orderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
        self.mapper = mapper
        self.makeAuthView = makeAuthView
        self.makeStoreDetailView = makeStoreDetailView
        self.makeReviewComposerView = makeReviewComposerView
    }

    func build() -> OrderDetailRootView {
        let router = OrderDetailRouter()
        let interactor = OrderDetailInteractor(
            orderID: orderID,
            orderRepository: orderRepository,
            sessionStore: sessionStore
        )
        let presenter = OrderDetailPresenter(
            initialOrderID: orderID,
            interactor: interactor,
            router: router,
            mapper: mapper
        )

        return OrderDetailRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeAuthView: makeAuthView,
            makeStoreDetailView: makeStoreDetailView,
            makeReviewComposerView: makeReviewComposerView
        )
    }
}
