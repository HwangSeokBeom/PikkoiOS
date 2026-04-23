import Foundation

struct DateParser: Sendable {
    func parseISO8601(_ string: String) -> Date? {
        if let date = fractionalSecondsFormatter.date(from: string) {
            return date
        }

        return plainISO8601Formatter.date(from: string)
    }

    func string(
        from date: Date,
        format: String,
        locale: Locale = Locale(identifier: "ko_KR"),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private var fractionalSecondsFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private var plainISO8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
