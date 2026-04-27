import SwiftUI

struct OrderDetailView: View {
    private enum Layout {
        static let cardHorizontalPadding: CGFloat = 20
        static let cardVerticalPadding: CGFloat = 22
        static let storeImageSize: CGFloat = 88
        static let itemImageSize: CGFloat = 88
        static let imageTextSpacing: CGFloat = 24
        static let itemVerticalSpacing: CGFloat = 7
        static let dateTopSpacing: CGFloat = 8
    }

    @ObservedObject var presenter: OrderDetailPresenter
    let imageLoader: any AuthorizedImageLoading
    let onAuthTap: () -> Void
    @State private var isCancelConfirmationPresented = false

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
                    .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset)
                }
            }
        }
        .navigationTitle("주문 상세")
        .navigationBarTitleDisplayMode(.inline)
        .alert("주문을 취소할까요?", isPresented: $isCancelConfirmationPresented) {
            Button("아니요", role: .cancel) {}
            Button("주문 취소", role: .destructive) {
                Task { await presenter.send(.cancelConfirmed) }
            }
        } message: {
            Text("주문이 취소되면 다시 되돌릴 수 없어요.")
        }
    }

    private var storeCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            HStack(alignment: .top, spacing: Layout.imageTextSpacing) {
                AuthorizedAsyncImage(
                    path: presenter.viewState.storeImagePath,
                    loader: imageLoader,
                    cornerRadius: PikkoRadius.card
                )
                .frame(width: Layout.storeImageSize, height: Layout.storeImageSize)
                .clipped()
                .layoutPriority(0)

                VStack(alignment: .leading, spacing: 0) {
                    Text(presenter.viewState.storeName)
                        .font(PikkoTypography.hero)
                        .foregroundStyle(PikkoColor.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    HStack(spacing: PikkoSpacing.xs) {
                        statusBadge
                        if let storeCategoryText = presenter.viewState.storeCategoryText {
                            TagChip(title: storeCategoryText, appearance: .subtle)
                        }
                    }
                    .padding(.top, PikkoSpacing.sm)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(presenter.viewState.createdAtText)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .padding(.top, Layout.dateTopSpacing)

                    if let storeCloseText = presenter.viewState.storeCloseText {
                        Text(storeCloseText)
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.accentStrong)
                            .padding(.top, PikkoSpacing.xs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
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
        .padding(.horizontal, Layout.cardHorizontalPadding)
        .padding(.vertical, Layout.cardVerticalPadding)
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
                orderItemRow(item)
            }
        }
        .padding(.horizontal, Layout.cardHorizontalPadding)
        .padding(.vertical, Layout.cardVerticalPadding)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private func orderItemRow(_ item: OrderDetailItemViewState) -> some View {
        HStack(alignment: .top, spacing: Layout.imageTextSpacing) {
            AuthorizedAsyncImage(
                path: item.imagePath,
                loader: imageLoader,
                cornerRadius: PikkoRadius.card
            )
            .frame(width: Layout.itemImageSize, height: Layout.itemImageSize)
            .clipped()
            .layoutPriority(0)

            VStack(alignment: .leading, spacing: Layout.itemVerticalSpacing) {
                Text(item.name)
                    .font(PikkoTypography.cardTitle)
                    .foregroundStyle(PikkoColor.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.quantityText)
                    .font(PikkoTypography.captionStrong)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.priceText)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            SectionHeader(title: "결제 및 메모")

            if let successMessage = presenter.viewState.cancelSuccessMessage {
                ToastView(message: successMessage, tone: .success)
            }

            if let errorMessage = presenter.viewState.cancelErrorMessage {
                ToastView(message: errorMessage, tone: .warning)
            }

            detailRow(title: "주문 번호", value: presenter.viewState.orderCode, valueLineLimit: 2)
            detailRow(title: "총 결제 금액", value: presenter.viewState.totalPriceText, valueLineLimit: 1)

            if let paymentStatusText = presenter.viewState.paymentStatusText {
                detailRow(title: "결제 상태", value: paymentStatusText, valueLineLimit: 2)
            }

            if let paymentMethodText = presenter.viewState.paymentMethodText {
                detailRow(title: "결제 수단", value: paymentMethodText, valueLineLimit: 2)
            }

            if let paidAtText = presenter.viewState.paidAtText {
                detailRow(title: "결제 일시", value: paidAtText, valueLineLimit: 2)
            }

            if let pickupTimeText = presenter.viewState.pickupTimeText {
                detailRow(title: "픽업 안내", value: pickupTimeText, valueLineLimit: 2)
            }

            if let memoText = presenter.viewState.memoText, !memoText.isEmpty {
                detailRow(title: "요청 메모", value: memoText, valueLineLimit: 4)
            }

            if presenter.viewState.orderStatus?.isCancellable == true {
                Divider()
                    .padding(.top, PikkoSpacing.sm)

                cancelOrderButton
            }
        }
        .padding(PikkoSpacing.xl)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private func detailRow(title: String, value: String, valueLineLimit: Int? = nil) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: PikkoSpacing.md) {
                detailTitle(title)

                detailValue(value, lineLimit: valueLineLimit)
            }

            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                detailTitle(title)
                    .frame(width: nil, alignment: .leading)

                detailValue(value, lineLimit: valueLineLimit)
            }
        }
    }

    private func detailTitle(_ title: String) -> some View {
        Text(title)
            .font(PikkoTypography.captionStrong)
            .foregroundStyle(PikkoColor.secondaryText)
            .frame(width: 88, alignment: .leading)
    }

    private func detailValue(_ value: String, lineLimit: Int?) -> some View {
        Text(value)
            .font(PikkoTypography.body)
            .foregroundStyle(PikkoColor.primaryText)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
    }

    private var cancelOrderButton: some View {
        Button {
            isCancelConfirmationPresented = true
        } label: {
            HStack(spacing: PikkoSpacing.xs) {
                if presenter.viewState.isCancelling {
                    ProgressView()
                        .tint(PikkoColor.danger)
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                }

                Text("주문 취소")
                    .font(PikkoTypography.bodyStrong)
            }
            .foregroundStyle(PikkoColor.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(PikkoColor.danger.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .stroke(PikkoColor.danger.opacity(0.35), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!presenter.viewState.canCancelOrder)
        .padding(.top, PikkoSpacing.xs)
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
