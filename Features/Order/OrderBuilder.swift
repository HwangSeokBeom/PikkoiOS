import SwiftUI

@MainActor
struct OrderBuilder {
    private let initialOrderID: String?
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let notificationService: AppNotificationService
    private let orderStatusSnapshotStore: OrderStatusSnapshotStore
    private let liveActivityManager: OrderLiveActivityManaging
    private let appConfiguration: AppConfiguration
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: () -> AnyView
    private let makeOrderDetailView: (String) -> AnyView
    private let makeCartView: () -> CartRootView
    private let makePaymentBridgeView: (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView
    private let onExploreHome: () -> Void

    init(
        initialOrderID: String? = nil,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        orderStatusSnapshotStore: OrderStatusSnapshotStore = InMemoryOrderStatusSnapshotStore(),
        liveActivityManager: OrderLiveActivityManaging = NoopOrderLiveActivityManager.shared,
        appConfiguration: AppConfiguration = AppConfiguration(),
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping () -> AnyView,
        makeOrderDetailView: @escaping (String) -> AnyView,
        makeCartView: @escaping () -> CartRootView,
        makePaymentBridgeView: @escaping (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView,
        onExploreHome: @escaping () -> Void
    ) {
        self.initialOrderID = initialOrderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.orderStatusSnapshotStore = orderStatusSnapshotStore
        self.liveActivityManager = liveActivityManager
        self.appConfiguration = appConfiguration
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeOrderDetailView = makeOrderDetailView
        self.makeCartView = makeCartView
        self.makePaymentBridgeView = makePaymentBridgeView
        self.onExploreHome = onExploreHome
    }

    func build() -> OrderRootView {
        let router = OrderRouter(onExploreHome: onExploreHome)
        let interactor = OrderInteractor(
            initialOrderID: initialOrderID,
            orderRepository: orderRepository,
            sessionStore: sessionStore,
            notificationService: notificationService,
            orderStatusSnapshotStore: orderStatusSnapshotStore,
            liveActivityManager: liveActivityManager,
            appConfiguration: appConfiguration
        )
        let presenter = OrderPresenter(interactor: interactor, router: router)

        return OrderRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeAuthView: makeAuthView,
            makeOrderDetailView: makeOrderDetailView,
            makeCartView: makeCartView,
            makePaymentBridgeView: makePaymentBridgeView
        )
    }
}
