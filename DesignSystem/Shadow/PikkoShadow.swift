import SwiftUI

struct PikkoShadowToken {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum PikkoShadow {
    static let card = PikkoShadowToken(
        color: Color.black.opacity(0.045),
        radius: 10,
        x: 0,
        y: 3
    )
    static let floating = PikkoShadowToken(
        color: Color.black.opacity(0.08),
        radius: 18,
        x: 0,
        y: 6
    )
    static let none = PikkoShadowToken(
        color: .clear,
        radius: 0,
        x: 0,
        y: 0
    )
}

extension View {
    func pikkoShadow(_ token: PikkoShadowToken) -> some View {
        shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}
