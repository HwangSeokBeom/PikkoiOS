import Foundation

@MainActor
final class OrderDetailPresenter: ObservableObject {
    @Published private(set) var viewState: OrderDetailViewState

    private let interactor: OrderDetailInteracting
    private let router: OrderDetailRouting
    private let mapper: OrderMapper
    private let dateParser = DateParser()

    private var hasLoaded = false

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
}
