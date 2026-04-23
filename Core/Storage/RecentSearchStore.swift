import Foundation

actor RecentSearchStore {
    private enum StorageKey {
        static let namespaces = "recent_search.namespaces"
    }

    private let store: any UserDefaultsStoring

    init(store: any UserDefaultsStoring) {
        self.store = store
    }

    func entries(for namespace: String) -> [String] {
        normalizedEntries()[namespace] ?? []
    }

    func record(_ term: String, for namespace: String, limit: Int = 10) {
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTerm.isEmpty else { return }

        var entriesByNamespace = normalizedEntries()
        var entries = entriesByNamespace[namespace] ?? []
        entries.removeAll { $0.caseInsensitiveCompare(normalizedTerm) == .orderedSame }
        entries.insert(normalizedTerm, at: 0)
        entriesByNamespace[namespace] = Array(entries.prefix(max(limit, 1)))
        persist(entriesByNamespace)
    }

    func remove(_ term: String, from namespace: String) {
        var entriesByNamespace = normalizedEntries()
        guard var entries = entriesByNamespace[namespace] else { return }
        entries.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        entriesByNamespace[namespace] = entries
        persist(entriesByNamespace)
    }

    func clear(namespace: String) {
        var entriesByNamespace = normalizedEntries()
        entriesByNamespace.removeValue(forKey: namespace)
        persist(entriesByNamespace)
    }

    func clearAll() {
        store.removeValue(forKey: StorageKey.namespaces)
    }

    private func normalizedEntries() -> [String: [String]] {
        store.codableValue([String: [String]].self, forKey: StorageKey.namespaces) ?? [:]
    }

    private func persist(_ entriesByNamespace: [String: [String]]) {
        do {
            try store.setCodable(entriesByNamespace, forKey: StorageKey.namespaces)
        } catch {
            Logger.shared.error("Failed to persist recent searches: \(error.localizedDescription)")
        }
    }
}
