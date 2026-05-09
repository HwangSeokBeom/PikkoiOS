import Foundation

enum CursorPagination {
    static func normalizedCursor(_ cursor: String?) -> String? {
        guard let cursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cursor.isEmpty,
              cursor != "0" else {
            return nil
        }

        return cursor
    }

    static func merged<Item, ID: Hashable>(
        existing: [Item],
        incoming: [Item],
        id: (Item) -> ID
    ) -> [Item] {
        var seen = Set<ID>()
        var result: [Item] = []
        result.reserveCapacity(existing.count + incoming.count)

        for item in existing + incoming {
            guard seen.insert(id(item)).inserted else { continue }
            result.append(item)
        }

        return result
    }
}
