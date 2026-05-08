import Foundation
import UIKit

private final class SendableImageCacheStorage: @unchecked Sendable {
    let cache = NSCache<NSURL, NSData>()
}

actor ImageCache {
    private let storage = SendableImageCacheStorage()
    private let logger = Logger(category: "ImageCache")

    init(
        countLimit: Int = 240,
        totalCostLimit: Int = 80 * 1024 * 1024
    ) {
        storage.cache.countLimit = countLimit
        storage.cache.totalCostLimit = totalCostLimit

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak storage] _ in
            storage?.cache.removeAllObjects()
            Logger(category: "ImageCache").debug("[ImageCache] clear reason=memoryWarning")
        }
    }

    func data(for url: URL) -> Data? {
        guard let object = storage.cache.object(forKey: url as NSURL) else {
            return nil
        }
        return object as Data
    }

    func insert(_ data: Data, for url: URL) {
        storage.cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        logger.debug("[ImageCache] store key=\(diagnosticKey(for: url)) cost=\(data.count)")
    }

    func removeValue(for url: URL) {
        storage.cache.removeObject(forKey: url as NSURL)
        logger.debug("[ImageCache] invalidate key=\(diagnosticKey(for: url))")
    }

    func removeAll() {
        storage.cache.removeAllObjects()
        logger.debug("[ImageCache] clear reason=memoryWarning")
    }

    private func diagnosticKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.path
    }
}
