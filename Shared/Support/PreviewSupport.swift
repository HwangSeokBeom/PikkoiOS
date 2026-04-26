import SwiftUI

struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ value: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

actor PreviewAuthorizedImageLoader: AuthorizedImageLoading {
    private var storage: [String: Data] = [:]

    func imageData(for path: String) async throws -> Data {
        if let stored = storage[path] {
            return stored
        }

        let data = PlaceholderImageFactory.makeData(seed: path)
        storage[path] = data
        return data
    }

    func cachedImageData(for path: String) async throws -> Data? {
        storage[path]
    }

    func removeCachedImage(for path: String) async throws {
        storage[path] = nil
    }
}
