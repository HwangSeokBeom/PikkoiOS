import Foundation

struct DistanceFormatter: Sendable {
    func string(fromMeters meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else {
            return "-"
        }

        switch meters {
        case 0..<1000:
            return "\(Int(meters.rounded()))m"
        case 1000..<10_000:
            let kilometers = meters / 1000
            return String(format: "%.1fkm", kilometers)
        default:
            return "\(Int((meters / 1000).rounded()))km"
        }
    }
}
