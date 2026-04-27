import Combine
import Foundation

@MainActor
final class OrderDetailPresenter: ObservableObject {
    @Published private(set) var viewState: OrderDetailViewState

    private let interactor: OrderDetailInteracting
    private let router: OrderDetailRouting
    private let mapper: OrderMapper
    private let dateParser = DateParser()

    private var hasLoaded = false
    private var cancellables = Set<AnyCancellable>()

    init(
        initialOrderID: String,
        interactor: OrderDetailInteracting,
        router: OrderDetailRouting,
        mapper: OrderMapper
    ) {
        self.viewState = OrderDetailViewState(orderID: initialOrderID)
        self.interactor = interactor
        self.router = router
        self.mapper = mapper
        bindOrderStatusChanges()
    }

    func send(_ action: OrderDetailAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
            guard viewState.isLoading else { return }
            await loadDetail()

        case .retryTapped:
            await loadDetail()

        case .storeTapped:
            guard let storeID = viewState.storeID else { return }
            router.routeToStoreDetail(storeID: storeID)

        case .reviewTapped:
            guard viewState.isReviewActionEnabled,
                  let storeID = viewState.storeID else { return }
            let mode: ReviewComposerMode
            if let reviewID = viewState.reviewID {
                mode = .edit(reviewID: reviewID)
            } else {
                mode = .create(orderCode: viewState.orderCode)
            }
            router.routeToReviewComposer(
                context: ReviewComposerContext(
                    storeID: storeID,
                    storeName: viewState.storeName,
                    mode: mode
                )
            )

        case .cancelConfirmed:
            await cancelOrder()

        case .loginRequiredTapped:
            router.routeToAuth()
        }
    }

    private func loadDetail() async {
        viewState.isLoading = true
        viewState.errorMessage = nil

        do {
            let detail = try await interactor.fetchOrderDetail()
            apply(detail: detail)
        } catch {
            apply(error: error)
        }

        viewState.isLoading = false
    }

    private func apply(detail: OrderDetail) {
        viewState.orderID = detail.orderID
        viewState.orderCode = detail.orderCode
        viewState.storeID = detail.storeID
        viewState.storeName = detail.storeName
        viewState.reviewID = detail.reviewID
        viewState.storeCategoryText = detail.storeCategory
        viewState.storeCloseText = detail.storeCloseTime.map { "마감 \($0)" }
        viewState.storeImagePath = detail.storeImagePath
        viewState.statusTitle = detail.status.displayTitle
        viewState.orderStatus = detail.status
        viewState.createdAtText = dateParser.string(from: detail.createdAt, format: "M월 d일 a h:mm")
        viewState.paidAtText = detail.paidAt.map { "결제 \($0.formatted(date: .abbreviated, time: .shortened))" }
        viewState.pickupTimeText = detail.pickupTime.map { "픽업 예상 \($0.formatted(date: .abbreviated, time: .shortened))" }
        viewState.totalPriceText = mapper.currencyText(for: detail.totalAmount)
        viewState.paymentStatusText = detail.paymentSummary?.statusText
        viewState.paymentMethodText = detail.paymentSummary?.methodText
        viewState.memoText = detail.userMemo
        viewState.items = detail.items.map {
            OrderDetailItemViewState(
                id: $0.id,
                name: $0.menuName,
                quantityText: "\($0.quantity)개",
                priceText: $0.unitPriceAmount.map(mapper.currencyText(for:)) ?? "-",
                imagePath: $0.imagePath
            )
        }
        viewState.timelineStages = detail.timeline.map { entry in
            OrderStatusTimelineView.Stage(
                id: entry.id,
                title: entry.status.displayTitle,
                timeText: entry.changedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "상태 대기 중",
                state: makeStageState(for: entry, currentStatus: detail.status)
            )
        }
        viewState.emptyState = nil
        viewState.hasLoadedContent = true
        applyReviewCTA(detail)
    }

    private func cancelOrder() async {
        guard viewState.canCancelOrder else { return }

        viewState.isCancelling = true
        viewState.cancelErrorMessage = nil
        viewState.cancelSuccessMessage = nil

        do {
            let detail = try await interactor.cancelOrder(orderCode: viewState.orderCode)
            apply(detail: detail)
            viewState.cancelSuccessMessage = "주문이 취소되었어요."
        } catch {
            let featureError = (error as? OrderFeatureError)
                ?? .unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
            viewState.cancelErrorMessage = featureError.userMessage
        }

        viewState.isCancelling = false
    }

    private func applyReviewCTA(_ detail: OrderDetail) {
        guard detail.status == .completed else {
            viewState.reviewActionTitle = nil
            viewState.isReviewActionEnabled = false
            return
        }

        if detail.reviewID != nil {
            viewState.reviewActionTitle = "리뷰 수정하기"
        } else {
            viewState.reviewActionTitle = "리뷰 작성하기"
        }
        viewState.isReviewActionEnabled = true
    }

    private func apply(error: Error) {
        let featureError = (error as? OrderFeatureError) ?? .unavailable(message: "주문 상세를 불러오지 못했어요.")
        viewState.hasLoadedContent = false
        viewState.emptyState = OrderEmptyState(
            title: featureError == .authenticationRequired ? "로그인이 필요해요" : "주문 상세를 불러오지 못했어요",
            message: featureError.userMessage,
            actionTitle: featureError == .authenticationRequired ? "로그인하러 가기" : "다시 시도",
            requiresAuthentication: featureError == .authenticationRequired
        )
    }

    private func makeStageState(
        for entry: OrderStatusTimelineEntry,
        currentStatus: OrderStatus
    ) -> OrderStatusTimelineView.StageState {
        if entry.status == currentStatus {
            return .current
        }
        return entry.completed ? .completed : .upcoming
    }

    private func bindOrderStatusChanges() {
        NotificationCenter.default.publisher(for: .pikkoOrderStatusDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[OrderStatusChangeNotificationUserInfoKey.event] as? OrderStatusChangeNotification else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.apply(statusChange: event)
                }
            }
            .store(in: &cancellables)
    }

    private func apply(statusChange event: OrderStatusChangeNotification) {
        guard viewState.orderCode == event.orderCode || event.orderID.map({ $0 == viewState.orderID }) == true else {
            return
        }

        viewState.orderStatus = event.status
        viewState.statusTitle = event.status.displayTitle

        viewState.timelineStages = viewState.timelineStages.map {
            OrderStatusTimelineView.Stage(
                id: $0.id,
                title: $0.title,
                timeText: $0.timeText,
                state: .completed
            )
        }

        if !viewState.timelineStages.contains(where: { $0.title == event.status.displayTitle }) {
            viewState.timelineStages.append(
                OrderStatusTimelineView.Stage(
                    id: "\(event.status.displayTitle)-\(event.orderCode)",
                    title: event.status.displayTitle,
                    timeText: "방금 전",
                    state: .current
                )
            )
        }
    }
}
