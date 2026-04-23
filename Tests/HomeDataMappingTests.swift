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
}
