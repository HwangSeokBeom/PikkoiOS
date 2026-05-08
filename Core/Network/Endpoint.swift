import Foundation

enum RequestTimeoutPreset: Sendable, Equatable {
    case `default`
    case upload
    case paymentValidation
    case custom(TimeInterval)

    func resolve(with configuration: AppConfiguration) -> TimeInterval {
        switch self {
        case .default:
            return configuration.defaultTimeout
        case .upload:
            return configuration.uploadTimeout
        case .paymentValidation:
            return configuration.paymentValidationTimeout
        case .custom(let interval):
            return interval
        }
    }
}

enum RequestBody: Sendable, Equatable {
    case json(Data)
    case raw(Data, contentType: String)
    case multipart(Data, boundary: String)

    var payload: Data {
        switch self {
        case .json(let data), .raw(let data, _), .multipart(let data, _):
            return data
        }
    }

    var contentType: String {
        switch self {
        case .json:
            return "application/json"
        case .raw(_, let contentType):
            return contentType
        case .multipart(_, let boundary):
            return "multipart/form-data; boundary=\(boundary)"
        }
    }
}

enum EndpointCachePolicy: Sendable, Equatable {
    case automatic
    case reloadIgnoringLocalCache
}

struct Endpoint<ResponseDTO: Decodable & Sendable>: Sendable {
    let path: String
    let method: HTTPMethod
    let query: [URLQueryItem]
    let headers: [String: String]
    let body: RequestBody?
    let timeout: RequestTimeoutPreset
    let authorizationPolicy: AuthorizationPolicy
    let cachePolicy: EndpointCachePolicy

    init(
        path: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: RequestBody? = nil,
        timeout: RequestTimeoutPreset = .default,
        authorizationPolicy: AuthorizationPolicy = .none,
        cachePolicy: EndpointCachePolicy = .automatic
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.authorizationPolicy = authorizationPolicy
        self.cachePolicy = cachePolicy
    }
}

struct EmptyResponse: Decodable, Equatable, Sendable {}
