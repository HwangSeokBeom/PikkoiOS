import XCTest
@testable import Pikko

@MainActor
final class CartFeatureTests: XCTestCase {
    func testCartInteractorBuildsStateWithImageAndPriceValidationNotice() async {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())
        cartStore.setQuantity(
            2,
            menuID: "menu-1",
            menuName: "카페라떼",
            unitPrice: 4500,
            imagePath: "/data/menus/latte.jpg",
            storeID: "store-1",
            storeName: "새싹 카페"
        )

        let interactor = CartInteractor(cartStore: cartStore)
        let state = await interactor.loadInitialState()

        XCTAssertEqual(state.storeID, "store-1")
        XCTAssertEqual(state.storeName, "새싹 카페")
        XCTAssertEqual(state.itemCountText, "2개")
        XCTAssertEqual(state.totalPriceText, "9,000원")
        XCTAssertEqual(state.items.first?.imagePath, "/data/menus/latte.jpg")
        XCTAssertEqual(state.items.first?.optionSummaryText, "기본 옵션")
        XCTAssertTrue(state.priceValidationNotice.contains("1개 항목"))
        XCTAssertTrue(state.isCheckoutEnabled)
    }

    func testCheckoutDraftBuildsPriceValidationRequest() throws {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())
        cartStore.setQuantity(
            1,
            menuID: "menu-1",
            menuName: "카페라떼",
            unitPrice: 4500,
            imagePath: "/data/menus/latte.jpg",
            storeID: "store-1",
            storeName: "새싹 카페"
        )
        cartStore.setQuantity(
            2,
            menuID: "menu-2",
            menuName: "휘낭시에",
            unitPrice: 3200,
            imagePath: nil,
            storeID: "store-1",
            storeName: "새싹 카페"
        )

        let draft = try XCTUnwrap(cartStore.makeCheckoutDraft())
        let request = draft.priceValidationRequest

        XCTAssertEqual(request.storeID, "store-1")
        XCTAssertEqual(request.items.count, 2)
        XCTAssertEqual(request.items[0].menuID, "menu-1")
        XCTAssertEqual(request.items[0].quantity, 1)
        XCTAssertEqual(request.items[1].menuID, "menu-2")
        XCTAssertEqual(request.items[1].quantity, 2)
        XCTAssertFalse(request.isEmpty)
    }
}
