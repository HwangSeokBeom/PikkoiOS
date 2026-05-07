import Foundation

@MainActor
protocol CartInteracting {
    func loadInitialState() async -> CartViewState
    func updateQuantity(for menuID: String, delta: Int) async -> CartViewState
}

@MainActor
struct CartInteractor: CartInteracting {
    private let cartStore: CartStore

    init(cartStore: CartStore) {
        self.cartStore = cartStore
    }

    func loadInitialState() async -> CartViewState {
        makeViewState()
    }

    func updateQuantity(for menuID: String, delta: Int) async -> CartViewState {
        guard let item = cartStore.items.first(where: { $0.menuID == menuID }) else {
            return makeViewState()
        }

        let nextQuantity = max(item.quantity + delta, 0)
        cartStore.setQuantity(
            nextQuantity,
            menuID: item.menuID,
            menuName: item.menuName,
            unitPrice: item.unitPrice,
            imagePath: item.imagePath,
            storeID: item.storeID,
            storeName: item.storeName
        )

        return makeViewState()
    }

    private func makeViewState() -> CartViewState {
        guard let draft = cartStore.makeCheckoutDraft() else {
            return CartViewState(
                emptyState: CartEmptyState(
                    title: "장바구니가 비어 있어요",
                    message: "메뉴를 담으면 이곳에서 수량과 합계를 확인할 수 있어요.\n가게 상세 화면에서 마음에 드는 메뉴를 장바구니에 담아보세요.",
                    systemImage: "cart"
                )
            )
        }

        return CartViewState(
            storeID: draft.storeID,
            storeName: draft.storeName,
            items: draft.items.map {
                CartItemViewState(
                    id: $0.menuID,
                    name: $0.menuName,
                    imagePath: $0.imagePath,
                    optionSummaryText: $0.optionSummaryText ?? "기본 옵션",
                    unitPriceText: $0.unitPriceText,
                    subtotalText: $0.subtotalText,
                    quantity: $0.quantity
                )
            },
            itemCountText: "\(draft.itemCount)개",
            totalPriceText: draft.subtotalText,
            priceValidationNotice: "현재 합계는 로컬 장바구니 기준이고, Checkout 직전 \(draft.priceValidationRequest.items.count)개 항목을 서버 가격 검증 입력으로 넘길 준비가 되어 있어요.",
            isCheckoutEnabled: !draft.isEmpty,
            checkoutDraft: draft,
            emptyState: nil
        )
    }
}
