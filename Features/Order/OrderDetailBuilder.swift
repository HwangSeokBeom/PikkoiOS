import SwiftUI

@MainActor
struct OrderDetailBuilder {
    private let orderID: String
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let mapper: OrderMapper
    private let appConfiguration: AppConfiguration
    private let makeAuthView: () -> AnyView
    private let makeStoreDetailView: (String) -> AnyView
    private let makeReviewComposerView: (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView
    private let makePaymentBridgeView: (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView

    init(
        orderID: String,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading,
        mapper: OrderMapper,
        appConfiguration: AppConfiguration = AppConfiguration(),
        makeAuthView: @escaping () -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView,
        makeReviewComposerView: @escaping (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView,
        makePaymentBridgeView: @escaping (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView
    ) {
        self.orderID = orderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
        self.mapper = mapper
        self.appConfiguration = appConfiguration
        self.makeAuthView = makeAuthView
        self.makeStoreDetailView = makeStoreDetailView
        self.makeReviewComposerView = makeReviewComposerView
        self.makePaymentBridgeView = makePaymentBridgeView
    }

    func build() -> OrderDetailRootView {
        let router = OrderDetailRouter()
        let interactor = OrderDetailInteractor(
            orderID: orderID,
            orderRepository: orderRepository,
            sessionStore: sessionStore,
            appConfiguration: appConfiguration
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
            makeReviewComposerView: makeReviewComposerView,
            makePaymentBridgeView: makePaymentBridgeView
        )
    }
}
