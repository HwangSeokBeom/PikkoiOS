import BackgroundTasks
import Foundation

@MainActor
protocol OrderBackgroundRefreshing: AnyObject {
    func register()
    func schedule()
    func refreshActiveOrders(source: OrderRefreshSource, force: Bool) async
}

enum OrderRefreshSource: String, Sendable {
    case foreground
    case background
    case pushTap
    case orderTab
}

@MainActor
final class OrderBackgroundRefreshCoordinator: OrderBackgroundRefreshing {
    static let taskIdentifier = "com.pikko.ios.order-refresh"

    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let liveActivityManager: OrderLiveActivityManaging
    private let logger = Logger(category: "OrderRefresh")
    private var isRegistered = false
    private var isScheduled = false
    private var refreshTask: Task<Void, Never>?

    init(
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        liveActivityManager: OrderLiveActivityManaging
    ) {
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.liveActivityManager = liveActivityManager
    }

    func register() {
        guard !isRegistered else { return }
        isRegistered = true
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handle(task: task)
            }
        }
        logger.debug("[OrderRefresh] register BGTask identifier=\(Self.taskIdentifier) registered=\(registered)")
    }

    func schedule() {
        guard sessionStore.isAuthenticated else {
            logger.debug("[OrderRefresh] schedule skipped reason=unsupported")
            return
        }

        Task { @MainActor in
            do {
                let page = try await orderRepository.fetchOrders(cursor: nil, filter: nil, forceRefresh: false)
                let activeCount = page.items.filter { !$0.status.isTerminal }.count
                logger.debug("[OrderRefresh] schedule requested activeOrderCount=\(activeCount)")
                guard activeCount > 0 else {
                    isScheduled = false
                    logger.debug("[OrderRefresh] schedule skipped reason=noActiveOrders")
                    return
                }
                guard !isScheduled else {
                    logger.debug("[OrderRefresh] schedule skipped reason=alreadyScheduled")
                    return
                }

                let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
                request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
                try BGTaskScheduler.shared.submit(request)
                isScheduled = true
            } catch {
                logger.warning("[OrderRefresh] schedule skipped reason=unsupported error=\(error.localizedDescription)")
            }
        }
    }

    func refreshActiveOrders(source: OrderRefreshSource, force: Bool) async {
        guard sessionStore.isAuthenticated else { return }
        logger.debug("[OrderRefresh] refresh start source=\(source.rawValue) force=\(force)")
        do {
            let page = try await orderRepository.fetchOrders(cursor: nil, filter: nil, forceRefresh: force)
            let activeOrders = page.items.filter { !$0.status.isTerminal }
            liveActivityManager.sync(orders: page.items, source: source.rawValue)
            logger.debug("[OrderRefresh] refresh success orderCount=\(page.items.count) activeCount=\(activeOrders.count)")
            if activeOrders.isEmpty {
                isScheduled = false
            } else if source != .background {
                schedule()
            }
        } catch let error as NetworkError {
            logger.warning("[OrderRefresh] refresh failed status=\(statusDescription(from: error)) retryable=\(error.isRetryableOrderRefreshFailure)")
        } catch is CancellationError {
            logger.debug("[OrderRefresh] refresh failed status=cancelled retryable=true")
        } catch {
            logger.warning("[OrderRefresh] refresh failed status=unknown retryable=true")
        }
    }

    private func handle(task: BGAppRefreshTask) {
        logger.debug("[OrderRefresh] handle start source=background")
        schedule()
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshActiveOrders(source: .background, force: true)
            task.setTaskCompleted(success: !Task.isCancelled)
            self.refreshTask = nil
        }
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.logger.warning("[OrderRefresh] handle expired")
                self?.refreshTask?.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    private func statusDescription(from error: NetworkError) -> String {
        switch error {
        case .unauthorized, .authenticationFailed:
            return "401"
        case .forbidden:
            return "403"
        case .accessTokenExpired:
            return "419"
        case .businessAuthorization:
            return "420"
        case .refreshTokenExpired:
            return "418"
        case .server:
            return "5xx"
        case .transport:
            return "transport"
        default:
            return "unknown"
        }
    }
}

private extension NetworkError {
    var isRetryableOrderRefreshFailure: Bool {
        switch self {
        case .transport, .server, .rateLimited, .accessTokenExpired:
            return true
        case .invalidRequest, .abnormalRequest, .configuration, .unauthorized, .authenticationFailed,
             .refreshTokenExpired, .forbidden, .notFound, .conflict, .businessAuthorization, .decoding:
            return false
        }
    }
}
