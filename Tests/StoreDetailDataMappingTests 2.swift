import XCTest
@testable import Pikko

@MainActor
final class StoreDetailDataMappingTests: XCTestCase {
    func testStoreMapperMapsStoreDetailAndResolvesAuthorizedPaths() throws {
        let data = """
        {
          "store_id": "store-1",
          "category": "카페",
          "name": "새싹 카페",
          "description": "향 좋은 커피를 제공해요.",
          "hashTags": ["#라떼맛집"],
          "open": "09:00",
          "close": "21:00",
          "address": "서울 영등포구 테스트로 1",
          "estimated_pickup_time": 15,
          "parking_guide": "주차 가능",
          "store_image_urls": ["/data/stores/store.jpg"],
          "is_picchelin": true,
          "is_pick": true,
          "pick_count": 12,
          "total_review_count": 9,
          "total_order_count": 31,
          "total_rating": 4.6,
          "creator": {
            "user_id": "user-1",
            "nick": "새싹점주",
            "profileImage": "/data/profiles/owner.png"
          },
          "geolocation": {
            "longitude": 126.9,
            "latitude": 37.5
          },
          "menu_list": [
            {
              "menu_id": "menu-1",
              "store_id": "store-1",
              "category": "대표 메뉴",
              "name": "라떼",
              "description": "고소한 라떼",
              "price": 4500,
              "is_sold_out": false,
              "tags": ["인기 1위"],
              "menu_image_url": "/data/menus/latte.jpg",
              "createdAt": "2025-07-25T10:00:00.000Z",
              "updatedAt": "2025-07-25T11:30:00.000Z"
            }
          ],
          "createdAt": "2025-07-20T08:00:00.000Z",
          "updatedAt": "2025-07-25T09:15:00.000Z"
        }
        """.data(using: .utf8)!

        let decoder = NetworkCoding.makeJSONDecoder()
        let dto = try decoder.decode(StoreDetailResponseDTO.self, from: data)
        let mapper = makeStoreMapper()

        let detail = mapper.mapDetail(dto)

        XCTAssertEqual(detail.id, "store-1")
        XCTAssertEqual(detail.imagePaths.first, "http://pickup.sesac.kr:42678/v1/data/stores/store.jpg")
        XCTAssertEqual(detail.owner?.profileImagePath, "http://pickup.sesac.kr:42678/v1/data/profiles/owner.png")
        XCTAssertEqual(detail.menus.first?.id, "menu-1")
        XCTAssertEqual(detail.menus.first?.imagePath, "http://pickup.sesac.kr:42678/v1/data/menus/latte.jpg")
    }

    func testReviewMapperNormalizesZeroCursorAndResolvesImages() throws {
        let data = """
        {
          "data": [
            {
              "review_id": "review-1",
              "content": "정말 맛있어요",
              "rating": 5,
              "review_image_urls": ["/data/reviews/review.jpg"],
              "order_menu_list": ["라떼", "휘낭시에"],
              "creator": {
                "user_id": "user-1",
                "nick": "새싹손님",
                "profileImage": "/data/profiles/user.png"
              },
              "user_total_review_count": 8,
              "user_total_rating": 4.5,
              "createdAt": "2025-07-21T14:00:00.000Z",
              "updatedAt": "2025-07-21T15:30:00.000Z"
            }
          ],
          "next_cursor": "0"
        }
        """.data(using: .utf8)!

        let decoder = NetworkCoding.makeJSONDecoder()
        let dto = try decoder.decode(ReviewListResponseDTO.self, from: data)
        let mapper = makeReviewMapper()

        let page = mapper.mapPage(dto)

        XCTAssertNil(page.nextCursor)
        XCTAssertEqual(page.items.first?.imagePaths.first, "http://pickup.sesac.kr:42678/v1/data/reviews/review.jpg")
        XCTAssertEqual(page.items.first?.author.profileImagePath, "http://pickup.sesac.kr:42678/v1/data/profiles/user.png")
    }

    func testCartStoreAggregatesMenuQuantitiesWithinSingleStore() {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())

        cartStore.setQuantity(
            2,
            menuID: "menu-1",
            menuName: "라떼",
            unitPrice: 4500,
            imagePath: nil,
            storeID: "store-1",
            storeName: "새싹 카페"
        )
        cartStore.setQuantity(
            1,
            menuID: "menu-2",
            menuName: "휘낭시에",
            unitPrice: 3200,
            imagePath: nil,
            storeID: "store-1",
            storeName: "새싹 카페"
        )

        XCTAssertEqual(cartStore.currentStoreID, "store-1")
        XCTAssertEqual(cartStore.quantity(for: "menu-1", in: "store-1"), 2)
        XCTAssertEqual(cartStore.summary.itemCount, 3)
        XCTAssertEqual(cartStore.summary.subtotalText, "12,200원")
    }

    func testCartStoreBuildsCheckoutDraftFromCurrentItems() {
        let cartStore = CartStore(cartRepository: InMemoryCartRepository())

        cartStore.setQuantity(
            2,
            menuID: "menu-1",
            menuName: "라떼",
            unitPrice: 4500,
            imagePath: nil,
            storeID: "store-1",
            storeName: "새싹 카페"
        )
        cartStore.setQuantity(
            1,
            menuID: "menu-2",
            menuName: "휘낭시에",
            unitPrice: 3200,
            imagePath: nil,
            storeID: "store-1",
            storeName: "새싹 카페"
        )

        let draft = cartStore.makeCheckoutDraft()

        XCTAssertEqual(draft?.storeID, "store-1")
        XCTAssertEqual(draft?.storeName, "새싹 카페")
        XCTAssertEqual(draft?.itemCount, 3)
        XCTAssertEqual(draft?.subtotalText, "12,200원")
        XCTAssertEqual(draft?.items.count, 2)
    }

    private func makeStoreMapper() -> StoreMapper {
        StoreMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )
    }

    private func makeReviewMapper() -> ReviewMapper {
        ReviewMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )
    }
}
