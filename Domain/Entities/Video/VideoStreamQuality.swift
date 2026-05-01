import Foundation

struct VideoStreamQuality: Equatable, Sendable, Identifiable {
    var id: String { quality }

    let quality: String
    let url: URL
    let urlPath: String

    init(quality: String, url: URL, urlPath: String? = nil) {
        self.quality = quality
        self.url = url
        self.urlPath = urlPath ?? url.absoluteString
    }

    init(quality: String, url: URL) {
        self.init(quality: quality, url: url, urlPath: url.absoluteString)
    }
}
