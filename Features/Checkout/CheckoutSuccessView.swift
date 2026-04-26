import SwiftUI

struct CheckoutSuccessView: View {
    @ObservedObject var presenter: CheckoutPresenter

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            VStack(spacing: PikkoSpacing.xl) {
                VStack(spacing: PikkoSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(iconBackgroundColor)
                            .frame(width: 88, height: 88)

                        Image(systemName: iconName)
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(iconForegroundColor)
                    }

                    Text(titleText)
                        .font(PikkoTypography.hero)
                        .foregroundStyle(PikkoColor.primaryText)

                    Text(
                        presenter.viewState.createdOrderCode.map { "주문번호 \($0)" }
                        ?? "생성된 주문 정보를 확인해 주세요."
                    )
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.accentStrong)

                    Text(
                        presenter.viewState.successMessage
                        ?? "장바구니를 정리했고, 다음 화면에서 주문 상태 흐름을 확인할 수 있어요."
                    )
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(PikkoSpacing.xl)
                .background(PikkoColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                .pikkoShadow(PikkoShadow.card)

                PrimaryButton(
                    title: "주문 내역 보기",
                    systemImage: "list.clipboard.fill",
                    isEnabled: presenter.viewState.createdOrderID != nil
                ) {
                    Task { await presenter.send(.orderHistoryTapped) }
                }
            }
            .padding(PikkoSpacing.xl)
        }
        .pikkoScreen(title: "주문 완료")
    }

    private var titleText: String {
        switch presenter.viewState.completionState {
        case .orderCreated:
            return "주문이 접수됐어요"
        case .paymentValidated:
            return "결제가 확인됐어요"
        case .validationPending:
            return "결제 확인이 지연되고 있어요"
        case .none:
            return "주문을 확인해 주세요"
        }
    }

    private var iconName: String {
        switch presenter.viewState.completionState {
        case .validationPending:
            return "clock.badge.exclamationmark.fill"
        case .none, .orderCreated, .paymentValidated:
            return "checkmark.circle.fill"
        }
    }

    private var iconBackgroundColor: Color {
        switch presenter.viewState.completionState {
        case .validationPending:
            return PikkoColor.warmYellow.opacity(0.22)
        case .none, .orderCreated, .paymentValidated:
            return PikkoColor.sage100
        }
    }

    private var iconForegroundColor: Color {
        switch presenter.viewState.completionState {
        case .validationPending:
            return PikkoColor.warmYellow
        case .none, .orderCreated, .paymentValidated:
            return PikkoColor.sage500
        }
    }
}
