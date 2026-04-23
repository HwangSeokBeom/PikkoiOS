import Foundation

struct CursorPage<Item: Equatable & Sendable>: Equatable, Sendable {
    let items: [Item]
    let nextCursor: String?
}
