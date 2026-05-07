import SwiftUI

struct CartView: View {
    private enum Layout {
        static let itemImageSize: CGFloat = 68
        static let imageTextSpacing: CGFloat = 12
        static let textControlSpacing: CGFloat = 8
        static let itemVerticalSpacing: CGFloat = 6
        static let quantityControlWidth: CGFloat = 100
        static let quantityControlHeight: CGFloat = 38
    }

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
                    .padding(.bottom, PikkoSpacing.xxl + RootTabBarMetrics.scrollContentBottomInset)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.viewState.hasActiveCart {
                bottomCTA
            }
        }
        .pikkoScreen(title: presenter.viewState.title)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(PikkoColor.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
        HStack(alignment: .top, spacing: Layout.imageTextSpacing) {
            AuthorizedAsyncImage(
                path: item.imagePath,
                loader: imageLoader,
                contentMode: .fill,
                cornerRadius: PikkoRadius.card,
                showsProgress: false
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

                Text(item.optionSummaryText)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text("\(item.unitPriceText) / 1개")
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(item.subtotalText)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.accentStrong)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                    .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: Layout.textControlSpacing)

            quantityControl(for: item)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
        }
        .frame(minHeight: Layout.itemImageSize, alignment: .top)
        .padding(.bottom, PikkoSpacing.lg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
    }

    private func quantityControl(for item: CartItemViewState) -> some View {
        HStack(spacing: PikkoSpacing.xs) {
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
        .padding(.horizontal, PikkoSpacing.xs)
        .frame(width: Layout.quantityControlWidth, height: Layout.quantityControlHeight)
        .background(PikkoColor.surfaceMuted)
        .clipShape(Capsule())
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
        .padding(.top, PikkoSpacing.sm)
        .padding(.bottom, PikkoSpacing.sm + RootTabBarMetrics.scrollContentBottomInset)
        .background(PikkoColor.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PikkoColor.divider)
                .frame(height: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: -3)
    }

    private func circleControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PikkoColor.primaryPressed)
                .frame(width: 24, height: 24)
                .background(PikkoColor.elevatedSurface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
