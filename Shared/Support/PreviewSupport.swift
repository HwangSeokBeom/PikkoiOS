import SwiftUI
import UIKit

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

        let data = PreviewImageFactory.makeData(seed: path)
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

enum PreviewImageFactory {
    static func makeData(seed: String, size: CGSize = CGSize(width: 900, height: 680)) -> Data {
        let palette = palettes[abs(seed.hashValue) % palettes.count]
        let image = UIGraphicsImageRenderer(size: size).image { rendererContext in
            let context = rendererContext.cgContext
            let colors = palette.map(\.cgColor) as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            context.setFillColor(UIColor.white.withAlphaComponent(0.28).cgColor)
            context.fillEllipse(in: CGRect(x: size.width * 0.08, y: size.height * 0.1, width: size.width * 0.22, height: size.width * 0.22))
            context.fillEllipse(in: CGRect(x: size.width * 0.72, y: size.height * 0.62, width: size.width * 0.16, height: size.width * 0.16))

            let initials = String(seed.prefix(2)).uppercased()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(size.width, size.height) * 0.18, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraph
            ]
            initials.draw(
                in: CGRect(
                    x: size.width * 0.18,
                    y: size.height * 0.32,
                    width: size.width * 0.64,
                    height: size.height * 0.3
                ),
                withAttributes: attributes
            )
        }

        return image.jpegData(compressionQuality: 0.92) ?? Data()
    }

    private static let palettes: [[UIColor]] = [
        [UIColor(red: 0.93, green: 0.96, blue: 0.88, alpha: 1), UIColor(red: 0.68, green: 0.79, blue: 0.63, alpha: 1)],
        [UIColor(red: 0.98, green: 0.90, blue: 0.78, alpha: 1), UIColor(red: 0.90, green: 0.71, blue: 0.43, alpha: 1)],
        [UIColor(red: 0.88, green: 0.95, blue: 0.92, alpha: 1), UIColor(red: 0.58, green: 0.76, blue: 0.70, alpha: 1)],
        [UIColor(red: 0.95, green: 0.92, blue: 0.84, alpha: 1), UIColor(red: 0.78, green: 0.74, blue: 0.60, alpha: 1)]
    ]
}
