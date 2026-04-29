import SwiftUI

struct OrderView: View {
    @ObservedObject var presenter: OrderPresenter
    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    let onExploreTap: () -> Void
    @State private var cancelCandidate: OrderListItemViewState?

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
                            ToastView(message: successMessage, tone: .success)
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
                .refreshable {
                    await presenter.send(.refreshRequested)
                }
            }
        }
        .alert("주문 취소 안내", isPresented: cancelConfirmationBinding) {
            Button("아니요", role: .cancel) {
                cancelCandidate = nil
            }
            Button("주문 취소", role: .destructive) {
                guard let orderID = cancelCandidate?.id else { return }
                cancelCandidate = nil
                Task { await presenter.send(.cancelConfirmed(orderID)) }
            }
        } message: {
            Text("결제 완료 주문 취소는 환불 처리가 필요합니다. 현재 앱에서는 지원 준비 중입니다.")
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
            Button(action: onTap) {
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

                    Spacer(minLength: PikkoSpacing.sm)

                    activeTimeline
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Layout.cardHorizontalPadding)
            .padding(.vertical, Layout.cardVerticalPadding)
            .background(PikkoColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
            .pikkoShadow(PikkoShadow.card)

            activeMenuCard

            if order.canCancel {
                cancelButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var activeTimeline: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            ForEach(order.statusSteps) { step in
                timelineStepRow(step)
            }
        }
        .padding(PikkoSpacing.md)
        .frame(minWidth: 124, alignment: .leading)
        .background(PikkoColor.gray100.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
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
        Button(action: onTap) {
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

                    AuthorizedAsyncImage(
                        path: order.storeImagePath,
                        loader: imageLoader,
                        cornerRadius: PikkoRadius.card
                    )
                    .frame(width: 78, height: 78)
                    .clipped()
                }

                if let reviewRatingText = order.reviewRatingText {
                    ratingPill(reviewRatingText)
                } else if order.canWriteReview {
                    Text("리뷰 작성")
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(PikkoColor.gray100)
                        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                } else {
                    Text(order.statusTitle)
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(PikkoColor.gray100)
                        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(Color(red: 1.0, green: 0.71, blue: 0.10))
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

                Text("주문 취소")
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
        .disabled(order.isCancelling)
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
