import Foundation

struct CheckoutMapper: Sendable {
    func mapValidationRequest(_ request: CheckoutPriceValidationRequest) -> CheckoutPriceValidationRequestDTO {
        CheckoutPriceValidationRequestDTO(
            storeID: request.storeID,
            orderMenuList: request.items.map {
                CheckoutPriceValidationLineItemDTO(
                    menuID: $0.menuID,
                    quantity: $0.quantity,
                    optionSummaryText: $0.optionSummaryText,
                    clientKnownUnitPrice: NSDecimalNumber(decimal: $0.clientKnownUnitPriceAmount).intValue,
                    clientKnownLinePrice: NSDecimalNumber(decimal: $0.clientKnownLinePriceAmount).intValue
                )
            },
            totalPrice: NSDecimalNumber(decimal: request.totalPriceAmount).intValue,
            couponID: request.couponID
        )
    }

    func mapValidationResponse(_ dto: CheckoutPriceValidationResponseDTO) -> CheckoutPriceValidationResult {
        CheckoutPriceValidationResult(
            validatedTotalPriceAmount: dto.validatedTotalPrice.map { Decimal($0) },
            issues: dto.issues.map(mapValidationIssue),
            message: dto.message
        )
    }

    private func mapValidationIssue(_ dto: CheckoutPriceValidationIssueDTO) -> CheckoutPriceValidationIssue {
        CheckoutPriceValidationIssue(
            id: dto.menuID ?? UUID().uuidString,
            menuID: dto.menuID,
            kind: mapValidationIssueKind(dto.kind),
            message: dto.message
        )
    }

    private func mapValidationIssueKind(_ value: String) -> CheckoutPriceValidationIssue.Kind {
        switch value {
        case "price_changed":
            return .priceChanged
        case "sold_out":
            return .soldOut
        case "menu_unavailable":
            return .menuUnavailable
        case "store_closed":
            return .storeClosed
        case "invalid_coupon":
            return .invalidCoupon
        default:
            return .unknown
        }
    }
}
