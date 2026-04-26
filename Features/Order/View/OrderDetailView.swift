import SwiftUI

struct OrderDetailView: View {
    @ObservedObject var presenter: OrderDetailPresenter
    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            if presenter.viewState.isLoading && !presenter.viewState.hasLoadedContent {
                LoadingView(message: "주문 상세를 준비하고 있어요")
                    .padding(PikkoSpacing.xl)
            } else if let emptyState = presenter.viewState.emptyState,
                      !presenter.viewState.hasLoadedContent {
                EmptyStateView(
                    title: emptyState.title,
                    message: emptyState.message,
                    systemImage: emptyState.requiresAuthentication ? "lock.circle.fill" : "exclamationmark.triangle.fill",
                    actionTitle: emptyState.actionTitle,
                    action: {
                        if emptyState.requiresAuthentication {
                            onAuthTap()
                        } else {
                            Task { await presenter.send(.retryTapped) }
                        }
                    }
                )
                .padding(PikkoSpacing.xl)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        storeCard
                        timelineCard
                        itemsCard
                        summaryCard
                    }
                    .padding(PikkoSpacing.xl)
                }
            }
        }
        .navigationTitle("주문 상세")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var storeCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            HStack(alignment: .top, spacing: PikkoSpacing.md) {
                AuthorizedAsyncImage(
                    path: presenter.viewState.storeImagePath,
                    loader: imageLoader,
                    cornerRadius: PikkoRadius.card
                )
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text(presenter.viewState.storeName)
                        .font(PikkoTypography.hero)
                        .foregroundStyle(PikkoColor.primaryText)

                    HStack(spacing: PikkoSpacing.xs) {
                        statusBadge
                        if let storeCategoryText = presenter.viewState.storeCategoryText {
                            TagChip(title: storeCategoryText, appearance: .subtle)
                        }
                    }

                    Text(presenter.viewState.createdAtText)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)

                    if let storeCloseText = presenter.viewState.storeCloseText {
                        Text(storeCloseText)
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.accentStrong)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if presenter.viewState.storeID != nil {
                SecondaryButton(
                    title: "가게 상세 보기",
                    systemImage: "storefront"
                ) {
                    Task { await presenter.send(.storeTapped) }
                }
            }

            if let reviewActionTitle = presenter.viewState.reviewActionTitle {
                PrimaryButton(
                    title: reviewActionTitle,
                    systemImage: presenter.viewState.reviewID == nil ? "star.bubble.fill" : "square.and.pencil",
                    isEnabled: presenter.viewState.isReviewActionEnabled
                ) {
                    Task { await presenter.send(.reviewTapped) }
                }
            }
        }
        .padding(PikkoSpacing.xl)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            SectionHeader(title: "주문 진행 상황")
            OrderStatusTimelineView(stages: presenter.viewState.timelineStages)
        }
        .padding(PikkoSpacing.xl)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            SectionHeader(title: "주문 메뉴")

            ForEach(presenter.viewState.items) { item in
                HStack(alignment: .top, spacing: PikkoSpacing.md) {
                    AuthorizedAsyncImage(
                        path: item.imagePath,
                        loader: imageLoader,
                        cornerRadius: PikkoRadius.card
                    )
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        Text(item.name)
                            .font(PikkoTypography.cardTitle)
                            .foregroundStyle(PikkoColor.primaryText)
                        Text(item.quantityText)
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.secondaryText)
                        Text(item.priceText)
                            .font(PikkoTypography.bodyStrong)
                            .foregroundStyle(PikkoColor.primaryText)
                    }
                    Spacer()
                }
            }
        }
        .padding(PikkoSpacing.xl)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            SectionHeader(title: "결제 및 메모")

            detailRow(title: "주문 번호", value: presenter.viewState.orderCode)
            detailRow(title: "총 결제 금액", value: presenter.viewState.totalPriceText)

            if let paymentStatusText = presenter.viewState.paymentStatusText {
                detailRow(title: "결제 상태", value: paymentStatusText)
            }

            if let paymentMethodText = presenter.viewState.paymentMethodText {
                detailRow(title: "결제 수단", value: paymentMethodText)
            }

            if let paidAtText = presenter.viewState.paidAtText {
                detailRow(title: "결제 일시", value: paidAtText)
            }

            if let pickupTimeText = presenter.viewState.pickupTimeText {
                detailRow(title: "픽업 안내", value: pickupTimeText)
            }

            if let memoText = presenter.viewState.memoText, !memoText.isEmpty {
                detailRow(title: "요청 메모", value: memoText)
            }
        }
        .padding(PikkoSpacing.xl)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: PikkoSpacing.md) {
            Text(title)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.secondaryText)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusBadge: some View {
        Text(presenter.viewState.statusTitle)
            .font(PikkoTypography.captionStrong)
            .foregroundStyle(PikkoColor.accentStrong)
            .padding(.horizontal, PikkoSpacing.sm)
            .frame(height: 30)
            .background(PikkoColor.sage50)
            .clipShape(Capsule())
    }
}
