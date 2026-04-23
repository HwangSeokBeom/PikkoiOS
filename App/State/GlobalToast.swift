import Foundation

struct GlobalToast: Equatable, Sendable, Identifiable {
    let id = UUID()
    let message: String
}
