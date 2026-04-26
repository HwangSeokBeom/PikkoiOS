import XCTest
@testable import Pikko

final class HomeDataMappingTests: XCTestCase {
    func testStoreMapperNormalizesZeroCursorToNil() throws {
        let decoder = NetworkCoding.makeJSONDecoder()
        let data = """
        {
          "data": [
            {
              "store_id": "store-1",
              "name": "새싹 카페",
              "store_image_urls": ["/data/stores/cafe.jpg"],
              "is_pick": true,
              "pick_count": 12,
              "hashTags": ["#티라미수"],
              "total_rating": 4.7,
              "total_order_count": 5,
              "total_review_count": 8,
              "geolocation": {
                "longitude": 126.9,
                "latitude": 37.5
              },
              "distance": 550.5
            }
          ],
          "next_cursor": "0"
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(StoreSummaryListResponseDTO.self, from: data)
        let mapper = StoreMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )

        let mappedPage = mapper.mapPage(response)

        XCTAssertEqual(mappedPage.items.first?.id, "store-1")
        XCTAssertEqual(mappedPage.items.first?.imagePaths.first, "http://pickup.sesac.kr:42678/v1/data/stores/cafe.jpg")
        XCTAssertNil(mappedPage.nextCursor)
    }

    func testBannerMapperResolvesRelativeBannerPath() {
        let mapper = BannerMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )

        let banner = mapper.map(
            BannerResponseDTO(
                name: "출석 이벤트",
                imageURL: "/data/banners/Pickup_0.png",
                payload: BannerPayloadDTO(type: "WEBVIEW", value: "/event-application")
            )
        )

        XCTAssertEqual(banner.id, "WEBVIEW:/event-application")
        XCTAssertEqual(banner.imagePath, "http://pickup.sesac.kr:42678/v1/data/banners/Pickup_0.png")
    }

    func testStoreMapperFiltersEmptyAndDuplicateImagePaths() throws {
        let mapper = StoreMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )

        let dto = try NetworkCoding.makeJSONDecoder().decode(
            StoreSummaryDTO.self,
            from: """
            {
              "store_id": "store-2",
              "name": "중복 이미지 가게",
              "store_image_urls": [
                " /data/stores/main.jpg ",
                "",
                "/data/stores/main.jpg",
                "/data/stores/detail.jpg"
              ],
              "is_pick": false,
              "pick_count": 0,
              "hashTags": [],
              "total_order_count": 0,
              "total_review_count": 0
            }
            """.data(using: .utf8)!
        )
        let store = mapper.map(dto)

        XCTAssertEqual(
            store.imagePaths,
            [
                "http://pickup.sesac.kr:42678/v1/data/stores/main.jpg",
                "http://pickup.sesac.kr:42678/v1/data/stores/detail.jpg"
            ]
        )
    }

    func testPopularStoresResponseDecodesWrappedDataPayload() throws {
        let data = """
        {
          "data": [
            {
              "store_id": "popular-1",
              "category": "디저트",
              "name": "새싹라운지",
              "store_image_urls": [
                "/data/stores/main.jpg",
                "/data/stores/sub.jpg"
              ],
              "is_picchelin": false,
              "is_pick": true,
              "pick_count": 126,
              "hashTags": ["#마카롱"],
              "total_rating": 0,
              "total_order_count": 0,
              "total_review_count": 0,
              "geolocation": {
                "longitude": 126.9,
                "latitude": 37.5
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try NetworkCoding.makeJSONDecoder().decode(PopularStoresResponseDTO.self, from: data)
        let mapper = makeStoreMapper()
        let firstDTO = try XCTUnwrap(response.data.first)
        let store = mapper.map(firstDTO)

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(store.id, "popular-1")
        XCTAssertEqual(store.imagePaths.count, 2)
        XCTAssertEqual(store.totalRating, 0)
        XCTAssertEqual(store.totalOrderCount, 0)
        XCTAssertEqual(store.totalReviewCount, 0)
        XCTAssertEqual(store.longitude, 126.9)
        XCTAssertEqual(store.latitude, 37.5)
    }

    func testPopularStoresResponseDecodesTopLevelArrayPayload() throws {
        let data = """
        [
          {
            "store_id": "popular-2",
            "category": "커피",
            "name": "배열 응답 카페",
            "store_image_urls": [],
            "is_pick": false,
            "pick_count": 0,
            "hashTags": [],
            "total_rating": 0,
            "total_order_count": 0,
            "total_review_count": 0
          }
        ]
        """.data(using: .utf8)!

        let response = try NetworkCoding.makeJSONDecoder().decode(PopularStoresResponseDTO.self, from: data)

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.storeID, "popular-2")
        XCTAssertEqual(response.data.first?.totalRating, 0)
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
}
