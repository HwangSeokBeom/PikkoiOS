import SwiftUI

struct CartView: View {
    @ObservedObject var presenter: CartPresenter
    let imageLoader: any AuthorizedImageLoading

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            if let emptyState = presenter.viewState.emptyState {
                EmptyStateView(
                    title: emptyState.title,
                    message: emptyState.message,
                    systemImage: emptyState.systemImage
                )
                .padding(PikkoSpacing.xl)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        storeSummaryCard

                        VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                            SectionHeader(
                                title: "담은 메뉴",
                                subtitle: "\(presenter.viewState.itemCountText) · \(presenter.viewState.totalPriceText)"
                            )

                            ForEach(presenter.viewState.items) { item in
                                itemRow(item)
                            }
                        }
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.top, PikkoSpacing.xl)
                    .padding(.bottom, PikkoSpacing.xxl + 84)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.viewState.hasActiveCart {
                bottomCTA
            }
        }
        .pikkoScreen(title: presenter.viewState.title)
    }

    private var storeSummaryCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text(presenter.viewState.storeName)
                .font(PikkoTypography.title)
                .foregroundStyle(PikkoColor.primaryText)

            Text("현재 장바구니는 한 가게 기준으로만 유지돼요.")
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)

            Text("최종 금액은 Checkout 직전 다시 확인돼요.")
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private func itemRow(_ item: CartItemViewState) -> some View {
        HStack(alignment: .top, spacing: PikkoSpacing.md) {
            AuthorizedAsyncImage(
                path: item.imagePath,
                loader: imageLoader,
                contentMode: .fill,
                cornerRadius: PikkoRadius.card,
                showsProgress: false
            )
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                Text(item.name)
                    .font(PikkoTypography.cardTitle)
                    .foregroundStyle(PikkoColor.primaryText)

                Text(item.optionSummaryText)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)

                Text("\(item.unitPriceText) / 1개")
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)

                Text(item.subtotalText)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.accentStrong)
            }

            Spacer(minLength: PikkoSpacing.md)

            HStack(spacing: PikkoSpacing.sm) {
                circleControl(systemImage: "minus") {
                    Task { await presenter.send(.decrementTapped(item.id)) }
                }

                Text("\(item.quantity)")
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
                    .frame(minWidth: 20)

                circleControl(systemImage: "plus") {
                    Task { await presenter.send(.incrementTapped(item.id)) }
                }
            }
            .padding(.horizontal, PikkoSpacing.sm)
            .frame(height: 40)
            .background(PikkoColor.surfaceMuted)
            .clipShape(Capsule())
        }
        .padding(.bottom, PikkoSpacing.lg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
    }

    private var bottomCTA: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presenter.viewState.totalPriceText)
                        .font(PikkoTypography.title)
                        .foregroundStyle(PikkoColor.primaryText)

                    Text("\(presenter.viewState.itemCountText) 준비 완료")
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }

                Spacer(minLength: PikkoSpacing.md)
            }

            Text(presenter.viewState.priceValidationNotice)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)

            PrimaryButton(
                title: presenter.viewState.primaryActionTitle,
                systemImage: "creditcard.fill",
                isEnabled: presenter.viewState.isCheckoutEnabled
            ) {
                Task { await presenter.send(.primaryButtonTapped) }
            }
        }
        .padding(.horizontal, PikkoSpacing.xl)
        .padding(.top, PikkoSpacing.md)
        .padding(.bottom, PikkoSpacing.md)
        .background(PikkoColor.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
    }

    private func circleControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PikkoColor.accentStrong)
                .frame(width: 28, height: 28)
                .background(.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
