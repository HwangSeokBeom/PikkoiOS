import Foundation

protocol UserDefaultsStoring: Sendable {
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func set(_ value: String?, forKey key: String)
    func set(_ value: Data?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func removeValue(forKey key: String)
    func codableValue<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value?
    func setCodable<Value: Encodable>(_ value: Value?, forKey key: String) throws
}

final class UserDefaultsStore: UserDefaultsStoring, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = NetworkCoding.makeJSONEncoder(),
        decoder: JSONDecoder = NetworkCoding.makeJSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }

    func bool(forKey key: String) -> Bool {
        userDefaults.bool(forKey: key)
    }

    func integer(forKey key: String) -> Int {
        userDefaults.integer(forKey: key)
    }

    func set(_ value: String?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    func set(_ value: Data?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    func set(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    func set(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    func removeValue(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    func codableValue<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(type, from: data)
    }

    func setCodable<Value: Encodable>(_ value: Value?, forKey key: String) throws {
        guard let value else {
            userDefaults.removeObject(forKey: key)
            return
        }

        let data = try encoder.encode(value)
        userDefaults.set(data, forKey: key)
    }
}
