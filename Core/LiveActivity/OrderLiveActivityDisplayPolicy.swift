import Foundation

enum OrderLiveActivityOrderCodeMode: String, Sendable {
    case short
    case medium
    case full
}

struct OrderLiveActivityOrderCodeDisplay: Equatable, Sendable {
    let text: String
    let mode: OrderLiveActivityOrderCodeMode
}

struct OrderLiveActivityStatusDisplay: Equatable, Sendable {
    let badge: String
    let compact: String
    let message: String
    let progress: Double
    let isTerminal: Bool

    static func map(status: String) -> OrderLiveActivityStatusDisplay {
        switch normalizedStatus(status) {
        case "PENDING_APPROVAL":
            return OrderLiveActivityStatusDisplay(
                badge: "대기",
                compact: "대기",
                message: "주문 확인 중",
                progress: 0.2,
                isTerminal: false
            )
        case "APPROVED":
            return OrderLiveActivityStatusDisplay(
                badge: "승인",
                compact: "승인",
                message: "주문이 승인됐어요",
                progress: 0.4,
                isTerminal: false
            )
        case "IN_PROGRESS":
            return OrderLiveActivityStatusDisplay(
                badge: "조리",
                compact: "조리",
                message: "메뉴 준비 중",
                progress: 0.65,
                isTerminal: false
            )
        case "READY_FOR_PICKUP":
            return OrderLiveActivityStatusDisplay(
                badge: "픽업",
                compact: "픽업",
                message: "픽업할 수 있어요",
                progress: 0.85,
                isTerminal: false
            )
        case "PICKED_UP":
            return OrderLiveActivityStatusDisplay(
                badge: "완료",
                compact: "완료",
                message: "픽업 완료",
                progress: 1.0,
                isTerminal: true
            )
        case "CANCELLED", "CANCELED":
            return OrderLiveActivityStatusDisplay(
                badge: "취소",
                compact: "취소",
                message: "주문 취소",
                progress: 0.0,
                isTerminal: true
            )
        case "REJECTED", "DENIED":
            return OrderLiveActivityStatusDisplay(
                badge: "거절",
                compact: "거절",
                message: "주문 거절",
                progress: 0.0,
                isTerminal: true
            )
        case "FAILED":
            return OrderLiveActivityStatusDisplay(
                badge: "실패",
                compact: "실패",
                message: "주문 실패",
                progress: 0.0,
                isTerminal: true
            )
        default:
            return OrderLiveActivityStatusDisplay(
                badge: "확인",
                compact: "확인",
                message: "상태 확인 중",
                progress: 0.0,
                isTerminal: false
            )
        }
    }

    private static func normalizedStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

enum OrderLiveActivityTextPolicy {
    static func displayTitle(_ title: String, maxLength: Int = 20) -> String {
        let normalized = normalizedSingleLine(title)
        let fallback = normalized.isEmpty ? "Pikko" : normalized
        guard fallback.count > maxLength, maxLength > 3 else {
            return fallback
        }
        return "\(fallback.prefix(maxLength - 3))..."
    }

    static func displayOrderCode(_ orderCode: String, mode: OrderLiveActivityOrderCodeMode) -> OrderLiveActivityOrderCodeDisplay {
        let normalized = normalizedSingleLine(orderCode)
        guard !normalized.isEmpty else {
            return OrderLiveActivityOrderCodeDisplay(text: "#----", mode: .short)
        }

        switch mode {
        case .short:
            return OrderLiveActivityOrderCodeDisplay(
                text: "#\(suffix(normalized, count: 4))",
                mode: .short
            )
        case .medium:
            if normalized.count <= 8 {
                return OrderLiveActivityOrderCodeDisplay(text: "Order \(normalized)", mode: .full)
            }
            return OrderLiveActivityOrderCodeDisplay(
                text: "Order \(prefix(normalized, count: 4))...\(suffix(normalized, count: 4))",
                mode: .medium
            )
        case .full:
            if normalized.count <= 12 {
                return OrderLiveActivityOrderCodeDisplay(text: "Order \(normalized)", mode: .full)
            }
            return displayOrderCode(normalized, mode: .medium)
        }
    }

    private static func normalizedSingleLine(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prefix(_ value: String, count: Int) -> String {
        String(value.prefix(max(0, count)))
    }

    private static func suffix(_ value: String, count: Int) -> String {
        String(value.suffix(max(0, count)))
    }
}
