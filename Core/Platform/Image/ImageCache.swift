import Foundation

actor ImageCache {
    private var storage: [URL: Data] = [:]

    func data(for url: URL) -> Data? {
        storage[url]
    }

    func insert(_ data: Data, for url: URL) {
        storage[url] = data
    }

    func removeValue(for url: URL) {
        storage.removeValue(forKey: url)
    }

    func removeAll() {
        storage.removeAll()
    }
}
