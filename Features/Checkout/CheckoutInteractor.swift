import Foundation

@MainActor
protocol CheckoutInteracting {
    func loadInitialState() async -> CheckoutViewState
    func validatePrice(input: CheckoutSubmissionInput) async throws -> CheckoutPriceValidationResult
    func validatePaymentConfigurationBeforeOrderCreation() async throws
    func createOrder(input: CheckoutSubmissionInput) async throws -> CreatedOrder
    func makePaymentRequest(createdOrder: CreatedOrder) async throws -> PaymentGatewayRequest
    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt
}

@MainActor
struct CheckoutInteractor: CheckoutInteracting {
    private let draft: CheckoutDraft
    private let orderRepository: OrderRepository
    private let appConfiguration: AppConfiguration
    private let sessionStore: SessionStore?
    private let placeholderAddress = CheckoutAddress.placeholder
    private let paymentMethod: CheckoutPaymentMethod = .card
    private let coupon: CheckoutCoupon? = nil

    init(
        draft: CheckoutDraft,
        orderRepository: OrderRepository,
        appConfiguration: AppConfiguration,
        sessionStore: SessionStore? = nil
    ) {
        self.draft = draft
        self.orderRepository = orderRepository
        self.appConfiguration = appConfiguration
        self.sessionStore = sessionStore
    }

    func loadInitialState() async -> CheckoutViewState {
        guard !draft.isEmpty else {
            return CheckoutViewState(isEmpty: true)
        }

        let priceValidationRequest = draft.priceValidationRequest

        return CheckoutViewState(
            storeName: draft.storeName,
            summaryText: "총 \(draft.itemCount)개 메뉴를 확인했고, 주문 생성 전 \(priceValidationRequest.items.count)개 항목의 가격 검증을 먼저 진행해요.",
            addressSummaryText: placeholderAddress.summaryText,
            paymentMethodSummaryText: paymentMethod.summaryText,
            couponSummaryText: coupon?.summaryText ?? "적용 쿠폰 없음",
            pickupMemo: "",
            items: draft.items.map {
                CheckoutItemViewState(
                    id: $0.menuID,
                    name: $0.menuName,
                    optionSummaryText: $0.optionSummaryText ?? "기본 옵션",
                    quantity: $0.quantity,
                    unitPriceText: $0.unitPriceText,
                    subtotalText: $0.subtotalText,
                    validationMessage: nil
                )
            },
            validationIssues: [],
            isValidatingPrice: false,
            isSubmittingOrder: false,
            isPaymentInProgress: false,
            isVerifyingPayment: false,
            totalPriceText: draft.subtotalText,
            primaryActionTitle: "주문 생성하기",
            isPrimaryEnabled: !draft.isEmpty,
            paymentWarningMessage: appConfiguration.shouldShowPaymentWarning
                ? "테스트 결제에서도 실제 금액이 결제될 수 있으며, PG 정책에 따라 자동 환불될 수 있습니다."
                : nil,
            isEmpty: false
        )
    }

    func validatePrice(input: CheckoutSubmissionInput) async throws -> CheckoutPriceValidationResult {
        guard !draft.isEmpty else {
            throw CheckoutFeatureError.validation(message: "장바구니가 비어 있어 주문을 생성할 수 없어요.")
        }

        let request = CheckoutPriceValidationRequest(
            storeID: draft.storeID,
            items: draft.items.map {
                CheckoutPriceValidationLineItem(
                    menuID: $0.menuID,
                    quantity: $0.quantity,
                    optionSummaryText: $0.optionSummaryText,
                    clientKnownUnitPriceAmount: $0.unitPriceAmount,
                    clientKnownLinePriceAmount: $0.subtotalAmount
                )
            },
            totalPriceAmount: draft.subtotalAmount,
            couponID: input.coupon?.code
        )

        guard !request.isEmpty else {
            throw CheckoutFeatureError.validation(message: "주문할 메뉴를 다시 확인해 주세요.")
        }

        do {
            return try await orderRepository.validatePrice(request)
        } catch let error as NetworkError {
            throw map(error: error)
        } catch let error as CheckoutFeatureError {
            throw error
        } catch {
            throw CheckoutFeatureError.unavailable(message: "가격 검증 중 알 수 없는 오류가 발생했어요.")
        }
    }

    func validatePaymentConfigurationBeforeOrderCreation() async throws {
        let diagnostics = makePaymentPreparationDiagnostics(
            createdOrder: nil,
            merchantUID: nil,
            amount: draft.subtotalAmount
        )
        logPaymentPreparationDiagnostics(diagnostics)

        let blockingIssues = diagnostics.filter(\.blocksPayment)
        guard blockingIssues.isEmpty else {
            let missingOrInvalidKeys = blockingIssues.map(\.key).joined(separator: ",")
            Logger.shared.error(
                "PortOne payment preparation blocked before order creation missingOrInvalidKeys=\(missingOrInvalidKeys) environment=\(appConfiguration.environment.rawValue)"
            )
            throw CheckoutFeatureError.configurationRequired
        }
    }

    func createOrder(input: CheckoutSubmissionInput) async throws -> CreatedOrder {
        guard !draft.isEmpty else {
            throw CheckoutFeatureError.validation(message: "장바구니가 비어 있어 주문을 생성할 수 없어요.")
        }

        let submission = CheckoutOrderSubmission(
            draft: draft,
            address: input.address ?? placeholderAddress,
            paymentMethod: input.paymentMethod,
            coupon: input.coupon,
            pickupMemo: input.pickupMemo
        )

        guard !submission.isEmpty else {
            throw CheckoutFeatureError.validation(message: "주문할 메뉴를 다시 확인해 주세요.")
        }

        do {
            return try await orderRepository.createOrder(submission)
        } catch let error as NetworkError {
            throw map(error: error)
        } catch let error as CheckoutFeatureError {
            throw error
        } catch {
            throw CheckoutFeatureError.unavailable(message: "주문 생성 중 알 수 없는 오류가 발생했어요.")
        }
    }

    func makePaymentRequest(createdOrder: CreatedOrder) async throws -> PaymentGatewayRequest {
        let merchantUID = createdOrder.orderCode.trimmingCharacters(in: .whitespacesAndNewlines)
        // 서버 검증이 최종 기준이며 클라이언트 금액은 신뢰하지 않는다.
        // 현재 Swagger의 주문 생성 응답에는 결제 준비 amount가 별도로 없어서,
        // POST /v1/orders 응답의 total_price를 PortOne 요청 금액으로 전달한다.
        let amount = createdOrder.totalPriceAmount > 0
            ? createdOrder.totalPriceAmount
            : draft.subtotalAmount
        let diagnostics = makePaymentPreparationDiagnostics(
            createdOrder: createdOrder,
            merchantUID: merchantUID,
            amount: amount
        )
        logPaymentPreparationDiagnostics(diagnostics)

        let blockingIssues = diagnostics.filter(\.blocksPayment)
        guard blockingIssues.isEmpty else {
            let missingOrInvalidKeys = blockingIssues.map(\.key).joined(separator: ",")
            Logger.shared.error(
                "PortOne payment preparation blocked missingOrInvalidKeys=\(missingOrInvalidKeys) orderCode=\(createdOrder.orderCode) environment=\(appConfiguration.environment.rawValue)"
            )
            throw CheckoutFeatureError.configurationRequired
        }

        guard !merchantUID.isEmpty else {
            throw CheckoutFeatureError.validation(message: "주문번호를 확인하지 못해 결제를 시작할 수 없어요.")
        }

        guard let userCode = appConfiguration.portOneUserCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userCode.isEmpty else {
            throw CheckoutFeatureError.configurationRequired
        }

        return PaymentGatewayRequest(
            orderID: createdOrder.id,
            merchantUID: merchantUID,
            amount: amount,
            orderName: makeOrderName(),
            buyerName: makeBuyerName(),
            pg: appConfiguration.portOnePg,
            pgID: appConfiguration.portOnePgID,
            payMethod: appConfiguration.portOnePayMethod,
            appScheme: appConfiguration.portOneAppScheme,
            userCode: userCode,
            isTestMode: appConfiguration.isPaymentTestMode
        )
    }

    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt {
        let trimmedImpUID = request.impUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImpUID.isEmpty else {
            throw CheckoutFeatureError.validation(message: "결제 완료 정보를 확인하지 못했어요.")
        }

        let validationRequest = PaymentValidationRequest(
            orderID: request.orderID,
            orderCode: request.orderCode,
            merchantUID: request.merchantUID,
            impUID: trimmedImpUID,
            success: request.success,
            errorMessage: request.errorMessage
        )

        do {
            return try await orderRepository.validatePayment(validationRequest)
        } catch let error as NetworkError {
            throw map(error: error)
        } catch let error as CheckoutFeatureError {
            throw error
        } catch {
            throw CheckoutFeatureError.unavailable(message: "결제 확인 중 알 수 없는 오류가 발생했어요.")
        }
    }

    private func makeOrderName() -> String {
        guard let firstItem = draft.items.first else {
            return draft.storeName
        }

        let remainingDistinctItemCount = max(draft.items.count - 1, 0)
        guard remainingDistinctItemCount > 0 else {
            return firstItem.menuName
        }

        return "\(firstItem.menuName) 외 \(remainingDistinctItemCount)개"
    }

    private func makeBuyerName() -> String {
        if let nick = sessionStore?.nick?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nick.isEmpty {
            return nick
        }
        return "Pikko 고객"
    }

    private func makePaymentPreparationDiagnostics(
        createdOrder: CreatedOrder?,
        merchantUID: String?,
        amount: Decimal
    ) -> [PaymentPreparationDiagnostic] {
        let portOneUserCodeDiagnostic = AppConfiguration.portOneUserCodeDiagnostic()
        let portOneUserCode = appConfiguration.portOneUserCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return [
            PaymentPreparationDiagnostic(
                key: "storeId",
                status: draft.storeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "ok",
                blocksPayment: draft.storeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            PaymentPreparationDiagnostic(
                key: "PORTONE_USER_CODE",
                status: portOneUserCode == nil
                    ? "missing_or_placeholder(\(portOneUserCodeDiagnostic.logStatus),buildSetting=PORTONE_USER_CODE)"
                    : "ok(\(portOneUserCodeDiagnostic.logStatus),buildSetting=PORTONE_USER_CODE)",
                blocksPayment: portOneUserCode == nil
            ),
            PaymentPreparationDiagnostic(
                key: "PORTONE_CHANNEL_KEY",
                status: "not_applicable_iamport_ios_uses_PORTONE_USER_CODE",
                blocksPayment: false
            ),
            PaymentPreparationDiagnostic(
                key: "paymentId",
                status: merchantUID?.nilIfEmpty == nil ? "pending_order_code" : "ok",
                blocksPayment: false
            ),
            PaymentPreparationDiagnostic(
                key: "redirectUrl",
                status: "not_applicable_iamport_ios_uses_appScheme",
                blocksPayment: false
            ),
            PaymentPreparationDiagnostic(
                key: "PORTONE_APP_SCHEME",
                status: appConfiguration.portOneAppScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "ok",
                blocksPayment: appConfiguration.portOneAppScheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            PaymentPreparationDiagnostic(
                key: "PORTONE_PG",
                status: appConfiguration.portOnePg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "ok",
                blocksPayment: appConfiguration.portOnePg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            PaymentPreparationDiagnostic(
                key: "PORTONE_PG_ID",
                status: appConfiguration.portOnePgID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty == nil ? "missing_optional" : "ok",
                blocksPayment: false
            ),
            PaymentPreparationDiagnostic(
                key: "PORTONE_PAY_METHOD",
                status: appConfiguration.portOnePayMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "ok",
                blocksPayment: appConfiguration.portOnePayMethod.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            PaymentPreparationDiagnostic(
                key: "amount",
                status: amount > 0 ? "ok" : "invalid_non_positive",
                blocksPayment: amount <= 0
            ),
            PaymentPreparationDiagnostic(
                key: "environmentPaymentMode",
                status: appConfiguration.blocksProductionPayment ? "invalid_production_uses_test_pg" : "ok",
                blocksPayment: appConfiguration.blocksProductionPayment
            )
        ]
    }

    private func logPaymentPreparationDiagnostics(_ diagnostics: [PaymentPreparationDiagnostic]) {
        let details = diagnostics
            .map { "\($0.key)=\($0.status)" }
            .joined(separator: " ")
        Logger.shared.debug(
            "PortOne payment configuration validation environment=\(appConfiguration.environment.rawValue) \(details)"
        )
    }

    private func map(error: NetworkError) -> CheckoutFeatureError {
        switch error {
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
            return .authenticationRequired
        case .invalidRequest:
            return .validation(message: "입력값 또는 결제 금액을 다시 확인해 주세요.")
        case .abnormalRequest(let message):
            return .validation(message: message)
        case .notFound(let message):
            return .notFound(message: message)
        case .businessAuthorization(let message):
            return .businessAuthorization(message: message)
        case .configuration:
            return .configurationRequired
        case .transport:
            return .unavailable(message: "네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "주문 응답을 해석하지 못했어요. 잠시 후 다시 시도해 주세요.")
        case .conflict(let message), .server(let message):
            return .unavailable(message: message)
        case .forbidden:
            return .businessAuthorization(message: "주문 생성 권한을 확인해 주세요.")
        case .rateLimited:
            return .unavailable(message: "요청이 많아요. 잠시 후 다시 시도해 주세요.")
        }
    }
}

private struct PaymentPreparationDiagnostic {
    let key: String
    let status: String
    let blocksPayment: Bool
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
