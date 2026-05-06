import XCTest
@testable import Pikko

final class MyReviewsRepositoryTests: XCTestCase {
    func testUserReviewsEndpointUsesUserPathQueryAndAccessToken() async throws {
        let apiClient = RecordingReviewAPIClient(
            response: UserReviewListResponseDTO(data: [], nextCursor: "cursor-2")
        )
        let dataSource = ReviewRemoteDataSource(apiClient: apiClient)

        _ = try await dataSource.fetchUserReviews(
            userID: "user-1",
            category: "카페",
            nextCursor: "cursor-1",
            limit: 20
        )

        XCTAssertEqual(apiClient.recordedPath, "/v1/stores/reviews/users/user-1")
        XCTAssertEqual(apiClient.recordedMethod, .get)
        XCTAssertEqual(apiClient.recordedAuthorizationPolicy, .accessToken)
        XCTAssertEqual(apiClient.recordedQueryValue("category"), "카페")
        XCTAssertEqual(apiClient.recordedQueryValue("next"), "cursor-1")
        XCTAssertEqual(apiClient.recordedQueryValue("limit"), "20")
    }

    func testUserReviewListResponseDecodesReviewPayload() throws {
        let data = """
        {
          "data": [
            {
              "review_id": "review-1",
              "content": "맛있고 빨랐어요",
              "rating": 5,
              "store": {
                "store_id": "store-1",
                "category": "카페",
                "name": "픽코 카페",
                "close": "21:00",
                "store_image_urls": ["/data/stores/store-1.jpg"],
                "is_picchelin": false,
                "is_pick": true,
                "pick_count": 7,
                "hashTags": ["커피"],
                "total_rating": 4.8,
                "total_order_count": 21,
                "total_review_count": 4
              },
              "review_image_urls": ["/data/reviews/review-1.jpg"],
              "order_menu_list": ["아메리카노"],
              "creator": {
                "user_id": "user-1",
                "nick": "픽코",
                "profileImage": null
              },
              "createdAt": "2026-05-06T03:00:00Z",
              "updatedAt": null
            }
          ],
          "next_cursor": "cursor-2"
        }
        """.data(using: .utf8)!

        let response = try NetworkCoding.makeJSONDecoder().decode(UserReviewListResponseDTO.self, from: data)

        XCTAssertEqual(response.data.first?.reviewID, "review-1")
        XCTAssertEqual(response.data.first?.store.id, "store-1")
        XCTAssertEqual(response.data.first?.creator.userID, "user-1")
        XCTAssertEqual(response.nextCursor, "cursor-2")
    }
}

private final class RecordingReviewAPIClient: APIClientProtocol, @unchecked Sendable {
    private let response: Any
    private(set) var recordedPath: String?
    private(set) var recordedMethod: HTTPMethod?
    private(set) var recordedQuery: [URLQueryItem] = []
    private(set) var recordedAuthorizationPolicy: AuthorizationPolicy?

    init(response: Any) {
        self.response = response
    }

    func execute<ResponseDTO>(_ endpoint: Endpoint<ResponseDTO>) async throws -> ResponseDTO where ResponseDTO: Decodable, ResponseDTO: Sendable {
        recordedPath = endpoint.path
        recordedMethod = endpoint.method
        recordedQuery = endpoint.query
        recordedAuthorizationPolicy = endpoint.authorizationPolicy

        guard let response = response as? ResponseDTO else {
            throw NetworkError.decoding
        }
        return response
    }

    func recordedQueryValue(_ name: String) -> String? {
        recordedQuery.first { $0.name == name }?.value
    }
}
