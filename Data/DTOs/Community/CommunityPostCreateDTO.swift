import Foundation

struct CommunityFileUploadResponseDTO: Decodable, Sendable {
    let files: [String]
}

struct CommunityPostCreateRequestDTO: Encodable, Sendable {
    let category: String
    let title: String
    let content: String
    let storeID: String?
    let latitude: Double
    let longitude: Double
    let files: [String]

    init(submission: CommunityPostDraftSubmission) throws {
        guard let latitude = submission.latitude,
              let longitude = submission.longitude else {
            throw NetworkError.invalidRequest
        }

        self.category = submission.category
        self.title = submission.title
        self.content = submission.content
        self.storeID = submission.storeID
        self.latitude = latitude
        self.longitude = longitude
        self.files = submission.filePaths ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case title
        case content
        case storeID = "store_id"
        case latitude
        case longitude
        case files
    }
}

struct CommunityPostUpdateRequestDTO: Encodable, Sendable {
    let category: String?
    let title: String?
    let content: String?
    let storeID: String?
    let latitude: Double?
    let longitude: Double?
    let files: [String]?

    init(submission: CommunityPostDraftSubmission) {
        self.category = submission.category
        self.title = submission.title
        self.content = submission.content
        self.storeID = submission.storeID
        self.latitude = submission.latitude
        self.longitude = submission.longitude
        self.files = submission.filePaths
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case title
        case content
        case storeID = "store_id"
        case latitude
        case longitude
        case files
    }
}
