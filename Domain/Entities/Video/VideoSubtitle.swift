import Foundation

struct VideoSubtitle: Equatable, Sendable, Identifiable {
    var id: String { "\(language)-\(name)" }

    let language: String
    let name: String
    let isDefault: Bool
    let url: URL
}
