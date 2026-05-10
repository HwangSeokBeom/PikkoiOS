import SwiftUI

struct OrderView: View {
    @ObservedObject var presenter: OrderPresenter
    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    let onExploreTap: () -> Void
    @State private var cancelCandidate: OrderListItemViewState?
    @State private var statusChangeCandidate: OrderStatusChangeCandidate?

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            if presenter.viewState.isInitialLoading && presenter.viewState.orders.isEmpty {
                LoadingView(message: "주문 내역을 준비하고 있어요")
                    .padding(PikkoSpacing.xl)
            } else if let emptyState = presenter.viewState.emptyState,
                      presenter.viewState.orders.isEmpty {
                EmptyStateView(
                    title: emptyState.title,
                    message: emptyState.message,
                    systemImage: emptyState.requiresAuthentication ? "lock.circle.fill" : "takeoutbag.and.cup.and.straw.fill",
                    actionTitle: emptyState.actionTitle,
                    action: {
                        if emptyState.requiresAuthentication {
                            onAuthTap()
                        } else if presenter.viewState.selectedFilter == .all {
                            onExploreTap()
                        } else {
                            Task { await presenter.send(.retryTapped) }
                        }
                    }
                )
                .padding(PikkoSpacing.xl)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        pickupNotice

                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                        }

                        if let successMessage = presenter.viewState.successMessage {
                            ToastView(
                                message: successMessage,
                                tone: .success,
                                actionTitle: presenter.viewState.hiddenOrderUndoCode == nil ? nil : "실행 취소",
                                action: presenter.viewState.hiddenOrderUndoCode.map { orderCode in
                                    {
                                        Task { await presenter.send(.undoHideOrderFromHistory(orderCode)) }
                                    }
                                }
                            )
                        }

                        if !activeOrders.isEmpty {
                            orderSection(title: "주문현황", orders: activeOrders)
                        }

                        if !historyOrders.isEmpty {
                            orderSection(title: "이전주문 내역", orders: historyOrders)
                        }

                        if presenter.viewState.isLoadingMore {
                            ProgressView()
                                .tint(PikkoColor.accentStrong)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, PikkoSpacing.lg)
                        }
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.top, PikkoSpacing.xl)
                    .padding(.bottom, PikkoSpacing.xl + RootTabBarMetrics.scrollContentBottomInset)
                }
                .contentMargins(.bottom, RootTabBarMetrics.scrollContentBottomInset, for: .scrollIndicators)
                .refreshable {
                    await presenter.send(.refreshRequested)
                }
            }
        }
        .alert(cancelCandidate?.isPaymentRecoveryCandidate == true ? "대기 주문을 정리할까요?" : "주문을 취소할까요?", isPresented: cancelConfirmationBinding) {
            Button("아니요", role: .cancel) {
                cancelCandidate = nil
            }
            Button(cancelCandidate?.isPaymentRecoveryCandidate == true ? "정리하기" : "주문 취소", role: .destructive) {
                guard let orderID = cancelCandidate?.id else { return }
                cancelCandidate = nil
                Task { await presenter.send(.cancelConfirmed(orderID)) }
            }
        } message: {
            Text(cancelCandidate?.isPaymentRecoveryCandidate == true ? "서버 주문을 취소하지 않고 이 기기의 주문현황에서만 숨겨요." : "취소 후에는 주문현황에서 제외돼요.")
        }
        .alert("주문 상태 변경", isPresented: statusChangeConfirmationBinding) {
            Button("취소", role: .cancel) {
                statusChangeCandidate = nil
            }
            Button("변경하기") {
                guard let candidate = statusChangeCandidate,
                      !isStatusChangeCandidateUpdating else { return }
                statusChangeCandidate = nil
                Task {
                    await presenter.send(
                        .statusChangeConfirmed(
                            orderCode: candidate.orderCode,
                            currentStatus: candidate.currentStatus,
                            nextStatus: candidate.nextStatus
                        )
                    )
                }
            }
            .disabled(isStatusChangeCandidateUpdating)
        } message: {
            if let candidate = statusChangeCandidate {
                Text("이 주문을 '\(candidate.nextStatus.displayTitle)'으로 변경할까요?")
            }
        }
        .onChange(of: presenter.viewState.orders) { _, orders in
            guard let candidate = statusChangeCandidate else { return }
            if !isValidStatusChangeCandidate(candidate, orders: orders) {
                statusChangeCandidate = nil
            }
        }
    }

    private var pickupNotice: some View {
        Text("픽업 하실 때는 주문번호를 꼭 말씀해주세요!")
            .font(PikkoTypography.bodyStrong)
            .foregroundStyle(PikkoColor.accentStrong)
            .frame(maxWidth: .infinity)
            .padding(.vertical, PikkoSpacing.md)
            .padding(.horizontal, PikkoSpacing.lg)
            .background(PikkoColor.surfaceMuted)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(PikkoColor.accent.opacity(0.25), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            .pikkoShadow(PikkoShadow.card)
    }

    private var activeOrders: [OrderListItemViewState] {
        presenter.viewState.orders.filter { !$0.isPastOrder }
    }

    private var historyOrders: [OrderListItemViewState] {
        presenter.viewState.orders.filter(\.isPastOrder)
    }

    private func orderSection(title: String, orders: [OrderListItemViewState]) -> some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            Text(title)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.secondaryText)

            LazyVStack(spacing: PikkoSpacing.md) {
                ForEach(orders) { order in
                    OrderRowView(
                        order: order,
                        imageLoader: imageLoader,
                        onTap: {
                            Task { await presenter.send(.orderTapped(order.id)) }
                        },
                        onCancelTap: {
                            cancelCandidate = order
                        },
                        onStatusSelect: { nextStatus in
                            guard let candidate = makeStatusChangeCandidate(order: order, nextStatus: nextStatus) else {
                                return
                            }
                            Task {
                                await presenter.send(
                                    .statusSelected(
                                        orderCode: order.orderCode,
                                        currentStatus: candidate.currentStatus,
                                        nextStatus: nextStatus
                                    )
                                )
                            }
                            statusChangeCandidate = candidate
                        },
                        onRefreshPaymentReceipt: {
                            Task {
                                await presenter.send(
                                    .paymentReceiptRefreshRequested(orderCode: order.orderCode, force: true)
                                )
                            }
                        },
                        onResumePayment: {
                            Task {
                                await presenter.send(.resumePendingPayment(order.orderCode))
                            }
                        },
                        onHideFromHistory: {
                            Task {
                                if order.isPaymentRecoveryCandidate {
                                    await presenter.send(.cancelConfirmed(order.id))
                                } else {
                                    await presenter.send(.hideOrderFromHistory(order.orderCode))
                                }
                            }
                        }
                    )
                    .onAppear {
                        Task { await presenter.send(.orderAppeared(order.id)) }
                    }
                }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PikkoSpacing.xs) {
                ForEach(OrderListFilter.allCases) { filter in
                    TagChip(
                        title: filter.title,
                        isSelected: presenter.viewState.selectedFilter == filter,
                        appearance: .outlined
                    ) {
                        Task { await presenter.send(.filterTapped(filter)) }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var cancelConfirmationBinding: Binding<Bool> {
        Binding(
            get: { cancelCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    cancelCandidate = nil
                }
            }
        )
    }

    private var statusChangeConfirmationBinding: Binding<Bool> {
        Binding(
            get: { statusChangeCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    statusChangeCandidate = nil
                }
            }
        )
    }

    private var isStatusChangeCandidateUpdating: Bool {
        guard let candidate = statusChangeCandidate else {
            return false
        }
        return presenter.viewState.orders.first { $0.orderCode == candidate.orderCode }?.isStatusUpdating == true
    }

    private func makeStatusChangeCandidate(
        order: OrderListItemViewState,
        nextStatus: OrderStatus
    ) -> OrderStatusChangeCandidate? {
        guard let latestOrder = presenter.viewState.orders.first(where: { $0.orderCode == order.orderCode }),
              !latestOrder.isStatusUpdating,
              latestOrder.status == order.status,
              latestOrder.status != nextStatus,
              latestOrder.allowedNextStatus == nextStatus else {
            return nil
        }

        return OrderStatusChangeCandidate(
            orderCode: latestOrder.orderCode,
            currentStatus: latestOrder.status,
            nextStatus: nextStatus
        )
    }

    private func isValidStatusChangeCandidate(
        _ candidate: OrderStatusChangeCandidate,
        orders: [OrderListItemViewState]
    ) -> Bool {
        guard let latestOrder = orders.first(where: { $0.orderCode == candidate.orderCode }) else {
            return false
        }
        return !latestOrder.isStatusUpdating
            && latestOrder.status == candidate.currentStatus
            && latestOrder.status != candidate.nextStatus
            && latestOrder.allowedNextStatus == candidate.nextStatus
    }
}

private struct OrderStatusChangeCandidate: Equatable {
    let orderCode: String
    let currentStatus: OrderStatus
    let nextStatus: OrderStatus
}

private struct OrderRowView: View {
    fileprivate enum Layout {
        static let cardHorizontalPadding: CGFloat = 18
        static let cardVerticalPadding: CGFloat = 18
        static let imageSize: CGFloat = 96
        static let imageTextSpacing: CGFloat = 20
        static let statusSpacing: CGFloat = 12
        static let textVerticalSpacing: CGFloat = 8
    }

    let order: OrderListItemViewState
    let imageLoader: any AuthorizedImageLoading
    let onTap: () -> Void
    let onCancelTap: () -> Void
    let onStatusSelect: (OrderStatus) -> Void
    let onRefreshPaymentReceipt: () -> Void
    let onResumePayment: () -> Void
    let onHideFromHistory: () -> Void

    var body: some View {
        Group {
            if order.isPastOrder {
                historyCard
                    .orderCardBackground(isHighlighted: order.isHighlighted)
            } else {
                activeCard
            }
        }
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            HStack(alignment: .top, spacing: Layout.imageTextSpacing) {
                VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
                    Text("주문번호 \(order.orderCode)")
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(PikkoColor.tertiaryText)

                    Text(order.storeName)
                        .font(PikkoTypography.hero)
                        .foregroundStyle(PikkoColor.accentStrong)
                        .lineLimit(2)

                    Text(order.createdAtText)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

                OrderStatusSelectorView(
                    currentStatus: order.status,
                    currentStatusTitle: order.currentStatusTitle,
                    isUpdating: order.isStatusUpdating,
                    paymentVerificationState: order.paymentVerificationState,
                    allowedNextStatus: order.allowedNextStatus,
                    disabledMessage: order.statusChangeMessage,
                    canRefreshPaymentReceipt: order.canRefreshPaymentReceipt,
                    onRefreshPaymentReceipt: onRefreshPaymentReceipt,
                    onSelectStatus: onStatusSelect
                )
            }
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .padding(.vertical, Layout.cardVerticalPadding)
            .background(PikkoColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            .pikkoShadow(PikkoShadow.card)

            activeMenuCard

            if order.isPaymentRecoveryCandidate {
                paymentRecoveryActions
            }

            if order.canCancel && !order.isPaymentRecoveryCandidate {
                cancelButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if !order.isPaymentRecoveryCandidate, let cancelDisabledReasonText = order.cancelDisabledReasonText {
                cancelUnavailableMessage
                    .accessibilityLabel(cancelDisabledReasonText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var paymentRecoveryActions: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                Text(order.paymentRecoveryTitle ?? "결제 미완료")
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
                Text(order.paymentRecoveryMessage ?? "결제를 완료해야 주문이 접수돼요.")
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
            }

            HStack(spacing: PikkoSpacing.sm) {
                Button(action: onResumePayment) {
                    HStack(spacing: PikkoSpacing.xs) {
                        if order.isPaymentRecoveryInProgress {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "creditcard")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(order.paymentRecoveryPrimaryActionTitle ?? "결제 이어하기")
                            .font(PikkoTypography.bodyStrong)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(PikkoColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(order.isPaymentRecoveryInProgress)

                Button(action: onHideFromHistory) {
                    HStack(spacing: PikkoSpacing.xs) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 13, weight: .semibold))
                        Text(order.paymentRecoverySecondaryActionTitle ?? "대기 주문 정리")
                            .font(PikkoTypography.captionStrong)
                    }
                    .foregroundStyle(PikkoColor.secondaryText)
                    .frame(width: 116, height: 46)
                    .background(PikkoColor.gray100)
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Layout.cardHorizontalPadding)
        .padding(.vertical, Layout.cardVerticalPadding)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var activeMenuCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(order.itemRows.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: PikkoSpacing.md) {
                    AuthorizedAsyncImage(
                        path: item.imagePath,
                        loader: imageLoader,
                        cornerRadius: PikkoRadius.card
                    )
                    .frame(width: 82, height: 62)
                    .clipped()

                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        Text(item.name)
                            .font(PikkoTypography.bodyStrong)
                            .foregroundStyle(PikkoColor.primaryText)
                            .lineLimit(2)

                        HStack(spacing: PikkoSpacing.sm) {
                            Text(item.priceText)
                                .font(PikkoTypography.body)
                                .foregroundStyle(PikkoColor.primaryText)

                            Text(item.quantityText)
                                .font(PikkoTypography.body)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, index == 0 ? 0 : PikkoSpacing.md)

                if index < order.itemRows.count - 1 {
                    Divider()
                        .padding(.leading, 82 + PikkoSpacing.md)
                }
            }

            Divider()
                .padding(.top, PikkoSpacing.md)

            HStack {
                Text("결제금액")
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.secondaryText)

                Spacer()

                Text(order.itemCountText)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)

                Text(order.totalPriceText)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
            }
            .padding(.top, PikkoSpacing.sm)
        }
        .padding(.horizontal, Layout.cardHorizontalPadding)
        .padding(.vertical, Layout.cardVerticalPadding)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            HStack(alignment: .top, spacing: Layout.imageTextSpacing) {
                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text(order.storeName)
                        .font(PikkoTypography.title)
                        .foregroundStyle(PikkoColor.primaryText)
                        .lineLimit(2)

                    Text("\(order.orderCode)   \(order.createdAtText)")
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineLimit(1)

                    Text(order.primaryItemText)
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineLimit(1)

                    Text(order.totalPriceText)
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.accentStrong)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)

                OrderStatusSelectorView(
                    currentStatus: order.status,
                    currentStatusTitle: order.currentStatusTitle,
                    isUpdating: order.isStatusUpdating,
                    paymentVerificationState: order.paymentVerificationState,
                    allowedNextStatus: order.allowedNextStatus,
                    disabledMessage: order.statusChangeMessage,
                    canRefreshPaymentReceipt: order.canRefreshPaymentReceipt,
                    onRefreshPaymentReceipt: onRefreshPaymentReceipt,
                    onSelectStatus: onStatusSelect
                )
            }

            if let reviewRatingText = order.reviewRatingText {
                ratingPill(reviewRatingText)
            } else if order.canWriteReview {
                Button(action: onTap) {
                    HStack(spacing: PikkoSpacing.xs) {
                        Image(systemName: "star.bubble.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("리뷰 작성")
                            .font(PikkoTypography.bodyStrong)
                    }
                    .foregroundStyle(PikkoColor.accentStrong)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(PikkoColor.sage50)
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if let reviewDisabledReasonText = order.reviewDisabledReasonText {
                reviewUnavailableMessage(reviewDisabledReasonText)
            }

            if order.canHideFromHistory {
                Button(action: onHideFromHistory) {
                    HStack(spacing: PikkoSpacing.xs) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 13, weight: .semibold))
                        Text("내역 숨기기")
                            .font(PikkoTypography.captionStrong)
                    }
                    .foregroundStyle(PikkoColor.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(PikkoColor.gray100)
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timelineStepRow(_ step: OrderProgressStepViewState) -> some View {
        HStack(spacing: PikkoSpacing.xs) {
            Image(systemName: iconName(for: step.state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color(for: step.state))

            Text(step.title)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(step.state == .pending ? PikkoColor.tertiaryText : PikkoColor.primaryText)
                .lineLimit(1)
        }
    }

    private func iconName(for state: OrderProgressStepViewState.State) -> String {
        switch state {
        case .completed, .current:
            return "checkmark.circle.fill"
        case .pending:
            return "circle"
        case .exception:
            return "exclamationmark.circle.fill"
        }
    }

    private func color(for state: OrderProgressStepViewState.State) -> Color {
        switch state {
        case .completed, .current:
            return PikkoColor.accent
        case .pending:
            return PikkoColor.gray300
        case .exception:
            return PikkoColor.danger
        }
    }

    private func ratingPill(_ ratingText: String) -> some View {
        HStack(spacing: PikkoSpacing.sm) {
            Image(systemName: "star.fill")
                .foregroundStyle(PikkoColor.warning)
            Text(ratingText)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(PikkoColor.gray100)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    @ViewBuilder
    private var headerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Layout.statusSpacing) {
                storeNameText
                    .lineLimit(1)

                Spacer(minLength: 0)

                statusBadge
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                storeNameText
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                statusBadge
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var storeNameText: some View {
        Text(order.storeName)
            .font(PikkoTypography.cardTitle)
            .foregroundStyle(PikkoColor.primaryText)
            .truncationMode(.tail)
            .layoutPriority(1)
    }

    @ViewBuilder
    private var priceAndDate: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PikkoSpacing.xs) {
                priceText
                separatorText
                createdAtText
            }

            VStack(alignment: .leading, spacing: PikkoSpacing.xxs) {
                priceText
                createdAtText
            }
        }
    }

    private var priceText: some View {
        Text(order.totalPriceText)
            .font(PikkoTypography.bodyStrong)
            .foregroundStyle(PikkoColor.primaryText)
            .lineLimit(1)
    }

    private var separatorText: some View {
        Text("·")
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.tertiaryText)
    }

    private var createdAtText: some View {
        Text(order.createdAtText)
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var statusBadge: some View {
        Text(order.statusTitle)
            .font(PikkoTypography.captionStrong)
            .foregroundStyle(PikkoColor.accentStrong)
            .padding(.horizontal, PikkoSpacing.sm)
            .frame(height: 28)
            .background(PikkoColor.sage50)
            .clipShape(Capsule())
    }

    private var cancelButton: some View {
        SwiftUI.Button {
            onCancelTap()
        } label: {
            HStack(spacing: PikkoSpacing.xs) {
                if order.isCancelling {
                    ProgressView()
                        .tint(PikkoColor.danger)
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(order.isPaymentRecoveryCandidate ? "대기 주문 정리" : "주문 취소")
                    .font(PikkoTypography.captionStrong)
            }
            .foregroundStyle(PikkoColor.danger)
            .frame(height: 34)
            .padding(.horizontal, PikkoSpacing.md)
            .background(PikkoColor.danger.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(PikkoColor.danger.opacity(0.32), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!order.isCancelEnabled || order.isCancelling)
    }

    private var cancelUnavailableMessage: some View {
        Text(order.cancelDisabledReasonText ?? "현재 주문은 앱에서 취소할 수 없어요.")
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.secondaryText)
            .padding(.vertical, PikkoSpacing.xs)
    }

    private func reviewUnavailableMessage(_ message: String) -> some View {
        Text(message)
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, PikkoSpacing.xs)
    }
}

private struct OrderStatusSelectorView: View {
    let currentStatus: OrderStatus
    let currentStatusTitle: String
    let isUpdating: Bool
    let paymentVerificationState: PaymentVerificationState
    let allowedNextStatus: OrderStatus?
    let disabledMessage: String?
    let canRefreshPaymentReceipt: Bool
    let onRefreshPaymentReceipt: () -> Void
    let onSelectStatus: (OrderStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            currentStatusRow

            if let allowedNextStatus {
                Button {
                    guard !isUpdating else { return }
                    onSelectStatus(allowedNextStatus)
                } label: {
                    HStack(spacing: PikkoSpacing.xs) {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(PikkoColor.accentStrong)
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(PikkoColor.accentStrong)
                        }

                        Text(actionTitle(for: allowedNextStatus))
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
            }

            if let disabledMessage {
                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text(disabledMessage)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(messageColor)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if canRefreshPaymentReceipt {
                        Button {
                            onRefreshPaymentReceipt()
                        } label: {
                            HStack(spacing: PikkoSpacing.xs) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold))

                                Text("결제 영수증 다시 확인")
                                    .font(PikkoTypography.captionStrong)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.86)
                            }
                            .foregroundStyle(PikkoColor.accentStrong)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isUpdating {
                ProgressView()
                    .controlSize(.small)
                    .tint(PikkoColor.accentStrong)
                    .padding(.top, 2)
                    .padding(.trailing, 2)
            }
        }
        .padding(PikkoSpacing.md)
        .frame(minWidth: 136, alignment: .leading)
        .background(PikkoColor.gray100.opacity(0.65))
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.accent.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .opacity(isUpdating ? 0.72 : 1)
    }

    private var currentStatusRow: some View {
        HStack(spacing: PikkoSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PikkoColor.accent)

            Text(currentStatusTitle)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.accentStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionTitle(for status: OrderStatus) -> String {
        switch status {
        case .accepted:
            return "주문승인으로 변경"
        case .preparing:
            return "조리 중으로 변경"
        case .ready:
            return "픽업대기로 변경"
        case .completed:
            return "픽업완료로 변경"
        case .pending:
            return "승인대기로 변경"
        case .cancelled:
            return "주문취소로 변경"
        case .rejected:
            return "주문거절로 변경"
        case .failed:
            return "주문실패로 변경"
        case .unknown:
            return "확인중으로 변경"
        }
    }

    private var messageColor: Color {
        switch paymentVerificationState {
        case .unchecked, .checking:
            return PikkoColor.secondaryText
        case .verified:
            return PikkoColor.accentStrong
        case .notVerified, .failed:
            return PikkoColor.danger
        }
    }
}

private extension View {
    func orderCardBackground(isHighlighted: Bool) -> some View {
        padding(.horizontal, OrderRowView.Layout.cardHorizontalPadding)
            .padding(.vertical, OrderRowView.Layout.cardVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .fill(isHighlighted ? PikkoColor.sage50 : PikkoColor.surfaceElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(isHighlighted ? PikkoColor.accent.opacity(0.35) : .clear, lineWidth: 1)
            }
            .pikkoShadow(PikkoShadow.card)
    }
}
