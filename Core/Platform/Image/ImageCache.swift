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
            Logger(category: "ImageCache").debug("[ImageCache] memoryWarning clear=true")
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
    }

    func removeValue(for url: URL) {
        storage.cache.removeObject(forKey: url as NSURL)
    }

    func removeAll() {
        storage.cache.removeAllObjects()
        logger.debug("[ImageCache] memoryWarning clear=true")
    }
}
