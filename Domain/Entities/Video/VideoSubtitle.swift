import Foundation

struct VideoSubtitle: Equatable, Sendable, Identifiable {
    var id: String { "\(language)-\(name)" }

    let language: String
    let name: String
    let isDefault: Bool
    let url: URL
    let format: VideoSubtitleFormat

    var languageCode: String { language }

    init(
        language: String,
        name: String,
        isDefault: Bool,
        url: URL,
        format: VideoSubtitleFormat = .webVTT
    ) {
        self.language = language
        self.name = name
        self.isDefault = isDefault
        self.url = url
        self.format = format
    }
}

enum VideoSubtitleFormat: String, Equatable, Sendable {
    case webVTT = "vtt"
    case srt
    case unknown

    init(rawValue: String?) {
        guard let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !normalized.isEmpty else {
            self = .webVTT
            return
        }

        if normalized == "webvtt" || normalized == "vtt" {
            self = .webVTT
        } else if normalized == "srt" {
            self = .srt
        } else {
            self = .unknown
        }
    }
}
