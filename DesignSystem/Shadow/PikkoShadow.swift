import SwiftUI

struct PikkoShadowToken {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum PikkoShadow {
    static let card = PikkoShadowToken(
        color: Color.black.opacity(0.08),
        radius: 12,
        x: 0,
        y: 4
    )
    static let floating = PikkoShadowToken(
        color: Color.black.opacity(0.12),
        radius: 18,
        x: 0,
        y: 8
    )
}

extension View {
    func pikkoShadow(_ token: PikkoShadowToken) -> some View {
        shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}
