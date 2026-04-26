import SwiftUI

struct OrderView: View {
    @ObservedObject var presenter: OrderPresenter
    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    let onExploreTap: () -> Void

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
                    VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                        filterChips

                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                        }

                        LazyVStack(spacing: PikkoSpacing.md) {
                            ForEach(presenter.viewState.orders) { order in
                                OrderRowView(
                                    order: order,
                                    imageLoader: imageLoader,
                                    onTap: {
                                        Task { await presenter.send(.orderTapped(order.id)) }
                                    }
                                )
                                .onAppear {
                                    Task { await presenter.send(.orderAppeared(order.id)) }
                                }
                            }

                            if presenter.viewState.isLoadingMore {
                                ProgressView()
                                    .tint(PikkoColor.accentStrong)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, PikkoSpacing.lg)
                            }
                        }
                    }
                    .padding(PikkoSpacing.xl)
                }
                .refreshable {
                    await presenter.send(.refreshRequested)
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
}

private struct OrderRowView: View {
    let order: OrderListItemViewState
    let imageLoader: any AuthorizedImageLoading
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: PikkoSpacing.md) {
                AuthorizedAsyncImage(
                    path: order.storeImagePath,
                    loader: imageLoader,
                    cornerRadius: PikkoRadius.card
                )
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    HStack(alignment: .center) {
                        Text(order.storeName)
                            .font(PikkoTypography.cardTitle)
                            .foregroundStyle(PikkoColor.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: PikkoSpacing.sm)

                        statusBadge
                    }

                    Text(order.primaryItemText)
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineLimit(2)

                    HStack(spacing: PikkoSpacing.xs) {
                        Text(order.totalPriceText)
                            .font(PikkoTypography.bodyStrong)
                            .foregroundStyle(PikkoColor.primaryText)

                        Text("·")
                            .foregroundStyle(PikkoColor.tertiaryText)

                        Text(order.createdAtText)
                            .font(PikkoTypography.caption)
                            .foregroundStyle(PikkoColor.secondaryText)
                    }

                    if let pickupTimeText = order.pickupTimeText {
                        Text(pickupTimeText)
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.accentStrong)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PikkoSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .fill(order.isHighlighted ? PikkoColor.sage50 : PikkoColor.surfaceElevated)
            )
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(order.isHighlighted ? PikkoColor.accent.opacity(0.35) : .clear, lineWidth: 1)
            }
            .pikkoShadow(PikkoShadow.card)
        }
        .buttonStyle(.plain)
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
}
