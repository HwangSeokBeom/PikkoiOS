import Foundation

struct CartViewState: Equatable {
    var title = "장바구니"
    var storeID = ""
    var storeName = ""
    var items: [CartItemViewState] = []
    var itemCountText = "0개"
    var totalPriceText = "0원"
    var priceValidationNotice = "현재 금액은 로컬 장바구니 기준이며, Checkout 직전 서버 검증을 붙일 준비가 되어 있어요."
    var primaryActionTitle = "Checkout 준비 화면으로 이동"
    var isCheckoutEnabled = false
    var checkoutDraft = CheckoutDraft.empty
    var emptyState: CartEmptyState?

    var hasActiveCart: Bool {
        emptyState == nil && !checkoutDraft.isEmpty
    }
}

struct CartEmptyState: Equatable {
    let title: String
    let message: String
    let systemImage: String
}

struct CartItemViewState: Identifiable, Equatable {
    let id: String
    let name: String
    let imagePath: String?
    let optionSummaryText: String
    let unitPriceText: String
    let subtotalText: String
    let quantity: Int
}
