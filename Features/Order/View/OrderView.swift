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
                    VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                        filterChips

                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                        }

                        if let successMessage = presenter.viewState.successMessage {
                            ToastView(message: successMessage, tone: .success)
                        }

                        LazyVStack(spacing: PikkoSpacing.md) {
                            ForEach(presenter.viewState.orders) { order in
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

                            if presenter.viewState.isLoadingMore {
                                ProgressView()
                                    .tint(PikkoColor.accentStrong)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, PikkoSpacing.lg)
                            }
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
        .alert("주문을 취소할까요?", isPresented: cancelConfirmationBinding) {
            Button("아니요", role: .cancel) {
                cancelCandidate = nil
            }
            Button("주문 취소", role: .destructive) {
                guard let orderID = cancelCandidate?.id else { return }
                cancelCandidate = nil
                Task { await presenter.send(.cancelConfirmed(orderID)) }
            }
        } message: {
            Text("주문이 취소되면 다시 되돌릴 수 없어요.")
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
    private enum Layout {
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
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: Layout.imageTextSpacing) {
                    AuthorizedAsyncImage(
                        path: order.storeImagePath,
                        loader: imageLoader,
                        cornerRadius: PikkoRadius.card
                    )
                    .frame(width: Layout.imageSize, height: Layout.imageSize)
                    .clipped()
                    .layoutPriority(0)

                    VStack(alignment: .leading, spacing: Layout.textVerticalSpacing) {
                        headerRow

                        Text(order.primaryItemText)
                            .font(PikkoTypography.body)
                            .foregroundStyle(PikkoColor.secondaryText)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        priceAndDate

                        if let pickupTimeText = order.pickupTimeText {
                            Text(pickupTimeText)
                                .font(PikkoTypography.captionStrong)
                                .foregroundStyle(PikkoColor.accentStrong)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if order.canCancel {
                cancelButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, Layout.cardHorizontalPadding)
        .padding(.vertical, Layout.cardVerticalPadding)
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
