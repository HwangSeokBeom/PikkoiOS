import Foundation

@MainActor
protocol CheckoutInteracting {
    func loadInitialState() async -> CheckoutViewState
    func validatePrice(input: CheckoutSubmissionInput) async throws -> CheckoutPriceValidationResult
    func createOrder(input: CheckoutSubmissionInput) async throws -> CreatedOrder
    func validatePayment(impUID: String) async throws -> ValidatedPaymentReceipt
}

@MainActor
struct CheckoutInteractor: CheckoutInteracting {
    private let draft: CheckoutDraft
    private let orderRepository: OrderRepository
    private let placeholderAddress = CheckoutAddress.placeholder
    private let paymentMethod: CheckoutPaymentMethod = .card
    private let coupon: CheckoutCoupon? = nil

    init(
        draft: CheckoutDraft,
        orderRepository: OrderRepository
    ) {
        self.draft = draft
        self.orderRepository = orderRepository
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
            totalPriceText: draft.subtotalText,
            primaryActionTitle: "주문 생성하기",
            isPrimaryEnabled: !draft.isEmpty,
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

    func validatePayment(impUID: String) async throws -> ValidatedPaymentReceipt {
        let trimmedImpUID = impUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImpUID.isEmpty else {
            throw CheckoutFeatureError.validation(message: "결제 완료 정보를 확인하지 못했어요.")
        }

        do {
            return try await orderRepository.validatePayment(impUID: trimmedImpUID)
        } catch let error as NetworkError {
            throw map(error: error)
        } catch let error as CheckoutFeatureError {
            throw error
        } catch {
            throw CheckoutFeatureError.unavailable(message: "결제 확인 중 알 수 없는 오류가 발생했어요.")
        }
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
