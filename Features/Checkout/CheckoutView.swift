import SwiftUI

struct CheckoutView: View {
    private enum Layout {
        static let estimatedBottomActionBarHeight: CGFloat = 260
        static let bottomContentGap: CGFloat = PikkoSpacing.xl
    }

    @ObservedObject var presenter: CheckoutPresenter
    @State private var bottomActionBarHeight = Layout.estimatedBottomActionBarHeight
    @State private var isPaymentConfigurationGuidePresented = false
    @FocusState private var isPickupMemoFocused: Bool

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            if presenter.viewState.isEmpty {
                EmptyStateView(
                    title: "확인할 주문이 없어요",
                    message: "장바구니에 담긴 메뉴가 있어야 Checkout 준비 화면을 열 수 있어요.",
                    systemImage: "creditcard"
                )
                .padding(PikkoSpacing.xl)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                            Text(presenter.viewState.storeName)
                                .font(PikkoTypography.title)
                                .foregroundStyle(PikkoColor.primaryText)

                            Text(presenter.viewState.summaryText)
                                .font(PikkoTypography.body)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PikkoSpacing.lg)
                        .background(PikkoColor.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                        .pikkoShadow(PikkoShadow.card)

                        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
                            SectionHeader(
                                title: "주문 입력 준비",
                                subtitle: presenter.viewState.createdOrderCode.map { "order_code \($0)" }
                            )

                            if presenter.viewState.isPaymentConfigurationBlocked {
                                paymentConfigurationWarningCard
                            } else if let paymentWarningMessage = presenter.viewState.paymentWarningMessage {
                                Text(paymentWarningMessage)
                                    .font(PikkoTypography.captionStrong)
                                    .foregroundStyle(PikkoColor.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(PikkoSpacing.md)
                                    .background(PikkoColor.point.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                            }

                            infoRow(
                                title: "수령 정보",
                                value: presenter.viewState.addressSummaryText
                            )
                            infoRow(
                                title: "결제 수단",
                                value: presenter.viewState.paymentMethodSummaryText
                            )
                            infoRow(
                                title: "쿠폰/할인",
                                value: presenter.viewState.couponSummaryText
                            )

                            VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                                Text("주문 요청 메모")
                                    .font(PikkoTypography.caption)
                                    .foregroundStyle(PikkoColor.secondaryText)

                                memoInput
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PikkoSpacing.lg)
                        .background(PikkoColor.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                        .pikkoShadow(PikkoShadow.card)

                        VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                            SectionHeader(
                                title: "주문 예정 메뉴",
                                subtitle: presenter.viewState.totalPriceText
                            )

                            if !presenter.viewState.validationIssues.isEmpty {
                                VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                                    ForEach(presenter.viewState.validationIssues) { issue in
                                        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                                            Text(issue.title)
                                                .font(PikkoTypography.captionStrong)
                                                .foregroundStyle(PikkoColor.danger)

                                            Text(issue.message)
                                                .font(PikkoTypography.caption)
                                                .foregroundStyle(PikkoColor.secondaryText)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(PikkoSpacing.md)
                                        .background(PikkoColor.point.opacity(0.14))
                                        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                                    }
                                }
                            }

                            ForEach(presenter.viewState.items) { item in
                                HStack(alignment: .top, spacing: PikkoSpacing.md) {
                                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                                        Text(item.name)
                                            .font(PikkoTypography.cardTitle)
                                            .foregroundStyle(PikkoColor.primaryText)

                                        Text(item.optionSummaryText)
                                            .font(PikkoTypography.caption)
                                            .foregroundStyle(PikkoColor.secondaryText)

                                        Text("\(item.quantity)개 · \(item.unitPriceText)")
                                            .font(PikkoTypography.caption)
                                            .foregroundStyle(PikkoColor.secondaryText)

                                        if let validationMessage = item.validationMessage {
                                            Text(validationMessage)
                                                .font(PikkoTypography.captionStrong)
                                                .foregroundStyle(PikkoColor.danger)
                                        }
                                    }

                                    Spacer(minLength: PikkoSpacing.md)

                                    Text(item.subtotalText)
                                        .font(PikkoTypography.bodyStrong)
                                        .foregroundStyle(PikkoColor.accentStrong)
                                }
                                .padding(.bottom, PikkoSpacing.lg)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(PikkoColor.divider)
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.top, PikkoSpacing.xl)
                    .padding(.bottom, scrollBottomInset)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.bottom, scrollBottomInset, for: .scrollIndicators)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: PikkoSpacing.md) {
                if let successMessage = presenter.viewState.successMessage {
                    Text(successMessage)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.sage500)
                } else if let errorMessage = presenter.viewState.errorMessage {
                    Text(errorMessage)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.danger)
                } else {
                    Text(helperMessage)
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }

                PrimaryButton(
                    title: presenter.viewState.primaryActionTitle,
                    systemImage: primaryActionSystemImage,
                    isLoading: presenter.viewState.isPrimaryLoading,
                    isEnabled: presenter.viewState.isPrimaryEnabled
                ) {
                    if presenter.viewState.isPaymentConfigurationBlocked {
                        isPaymentConfigurationGuidePresented = true
                    }
                    Task { await presenter.send(.primaryButtonTapped) }
                }
            }
            .padding(.horizontal, PikkoSpacing.xl)
            .padding(.top, PikkoSpacing.md)
            .padding(.bottom, bottomActionBarBottomPadding)
            .background(PikkoColor.surfaceElevated)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateBottomActionBarHeight(proxy.size.height)
                        }
                        .onChange(of: proxy.size.height) { _, height in
                            updateBottomActionBarHeight(height)
                        }
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(PikkoColor.divider)
                    .frame(height: 1)
            }
        }
        .pikkoScreen(title: presenter.viewState.title)
        .alert("결제 설정 확인하기", isPresented: $isPaymentConfigurationGuidePresented) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(paymentConfigurationGuideText)
        }
    }

    private var scrollBottomInset: CGFloat {
        bottomActionBarHeight
            + (isPickupMemoFocused ? 0 : RootTabBarMetrics.scrollContentBottomInset)
            + Layout.bottomContentGap
    }

    private var bottomActionBarBottomPadding: CGFloat {
        PikkoSpacing.sm + (isPickupMemoFocused ? 0 : RootTabBarMetrics.contentHeight)
    }

    private var helperMessage: String {
        if presenter.viewState.isPaymentConfigurationBlocked {
            return presenter.viewState.paymentConfigurationDiagnosticMessage
                ?? "Config/Secrets.xcconfig에 실제 PortOne 가맹점 식별코드를 설정한 뒤 Clean Build 하세요."
        }

        if presenter.viewState.paymentBridgeContext != nil {
            return "결제 창을 통해 결제를 완료한 뒤 서버 검증을 이어서 진행합니다."
        }

        if presenter.viewState.isValidatingPrice {
            return "주문 금액과 메뉴 상태를 먼저 확인하고 있어요."
        }

        if presenter.viewState.isSubmittingOrder {
            return "가격 검증이 끝나서 주문 생성 요청을 보내고 있어요."
        }

        if presenter.viewState.isVerifyingPayment {
            return "PG 결제 결과를 서버에 확인하고 있어요."
        }

        if presenter.viewState.isPaymentInProgress {
            return "PortOne 결제창에서 결제를 진행하고 있어요."
        }

        return "가격 검증을 먼저 수행한 뒤 주문을 생성하고, 결제 성공 시 서버 검증까지 이어집니다."
    }

    private var primaryActionSystemImage: String {
        presenter.viewState.isPaymentConfigurationBlocked ? "gearshape.fill" : "creditcard.fill"
    }

    private var paymentConfigurationWarningCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text("Config/Secrets.xcconfig에 PORTONE_USER_CODE를 실제 PortOne 가맹점 식별코드로 설정한 뒤 Clean Build 하세요.")
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.danger)
                .fixedSize(horizontal: false, vertical: true)

            if let diagnostic = presenter.viewState.paymentConfigurationDiagnostic {
                VStack(alignment: .leading, spacing: 4) {
                    diagnosticText("source", diagnostic.source)
                    diagnosticText("state", diagnostic.state)
                    diagnosticText("rawMasked", diagnostic.rawMasked)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PikkoSpacing.md)
        .background(PikkoColor.point.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private func diagnosticText(_ title: String, _ value: String) -> some View {
        Text("\(title)=\(value)")
            .font(PikkoTypography.caption)
            .foregroundStyle(PikkoColor.secondaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var paymentConfigurationGuideText: String {
        """
        1. 터미널에서:
        cp Config/Secrets.xcconfig.sample Config/Secrets.xcconfig
        2. Config/Secrets.xcconfig 열기
        3. PORTONE_USER_CODE = imp실제값 으로 변경
        4. Xcode Product > Clean Build Folder
        5. 다시 실행 후 로그에서 userCodeState=valid 확인
        """
    }

    private func updateBottomActionBarHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        guard abs(bottomActionBarHeight - height) > 1 else { return }
        bottomActionBarHeight = height
        Logger.shared.debug("[Checkout] bottomPaymentBarHeight=\(height) scrollBottomInset=\(scrollBottomInset)")
    }

    private var pickupMemoBinding: Binding<String> {
        Binding(
            get: { presenter.viewState.pickupMemo },
            set: { newValue in
                Task { await presenter.send(.pickupMemoChanged(newValue)) }
            }
        )
    }

    private var memoInput: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: pickupMemoBinding)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.primaryText)
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, PikkoSpacing.md)
                .padding(.vertical, PikkoSpacing.sm)
                .frame(height: 104)
                .focused($isPickupMemoFocused)

            if presenter.viewState.pickupMemo.isEmpty {
                Text("가게에 전달할 요청사항이 있으면 입력해 주세요")
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2...3)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
                    .padding(.horizontal, PikkoSpacing.lg)
                    .padding(.vertical, PikkoSpacing.md)
            }
        }
        .frame(height: 104, alignment: .topLeading)
        .background(PikkoColor.surfaceMuted)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                .stroke(PikkoColor.line.opacity(0.65), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: PikkoSpacing.md) {
            Text(title)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.primaryText)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }
}
