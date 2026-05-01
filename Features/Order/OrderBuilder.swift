import SwiftUI

@MainActor
struct OrderBuilder {
    private let initialOrderID: String?
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let notificationService: AppNotificationService
    private let orderStatusSnapshotStore: OrderStatusSnapshotStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: () -> AnyView
    private let makeOrderDetailView: (String) -> AnyView
    private let onExploreHome: () -> Void

    init(
        initialOrderID: String? = nil,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        orderStatusSnapshotStore: OrderStatusSnapshotStore = InMemoryOrderStatusSnapshotStore(),
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping () -> AnyView,
        makeOrderDetailView: @escaping (String) -> AnyView,
        onExploreHome: @escaping () -> Void
    ) {
        self.initialOrderID = initialOrderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.orderStatusSnapshotStore = orderStatusSnapshotStore
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeOrderDetailView = makeOrderDetailView
        self.onExploreHome = onExploreHome
    }

    func build() -> OrderRootView {
        let router = OrderRouter(onExploreHome: onExploreHome)
        let interactor = OrderInteractor(
            initialOrderID: initialOrderID,
            orderRepository: orderRepository,
            sessionStore: sessionStore,
            notificationService: notificationService,
            orderStatusSnapshotStore: orderStatusSnapshotStore
        )
        let presenter = OrderPresenter(interactor: interactor, router: router)

        return OrderRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeAuthView: makeAuthView,
            makeOrderDetailView: makeOrderDetailView
        )
    }
}
