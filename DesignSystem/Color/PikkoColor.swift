import SwiftUI
import UIKit

enum PikkoColor {
    static let primary = adaptive(light: 0xFF5A3C, dark: 0xFF7A5F)
    static let primarySoft = adaptive(light: 0xFFF0EC, dark: 0x3A201A)
    static let primaryPressed = adaptive(light: 0xE94B30, dark: 0xFF8D74)

    static let groupedBackground = adaptive(light: 0xFFF8F3, dark: 0x141210)
    static let background = groupedBackground
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1D1916)
    static let elevatedSurface = adaptive(light: 0xFFFDFB, dark: 0x25201C)
    static let surfaceElevated = elevatedSurface
    static let surfaceMuted = primarySoft

    static let textPrimary = adaptive(light: 0x1F1F1F, dark: 0xF7F2EE)
    static let textSecondary = adaptive(light: 0x6B625D, dark: 0xBDB2AA)
    static let textTertiary = adaptive(light: 0xA39A94, dark: 0x8F837A)
    static let divider = adaptive(light: 0xEFE7E2, dark: 0x3A312B)

    static let success = adaptive(light: 0x2EAD6B, dark: 0x43C983)
    static let warning = adaptive(light: 0xF5A524, dark: 0xF8BA46)
    static let error = adaptive(light: 0xE5484D, dark: 0xFF6B70)

    static let warmWhite = groupedBackground
    static let warmYellow = warning
    static let coralHeart = primary

    static let ink900 = textPrimary
    static let gray100 = adaptive(light: 0xF8F2EE, dark: 0x241F1B)
    static let gray200 = divider
    static let gray300 = adaptive(light: 0xDDD3CD, dark: 0x4D423A)
    static let gray400 = textTertiary
    static let gray500 = textSecondary
    static let gray600 = adaptive(light: 0x4E4641, dark: 0xD0C5BD)

    static let sage50 = primarySoft
    static let sage100 = adaptive(light: 0xFFE2DA, dark: 0x4A281F)
    static let sage300 = adaptive(light: 0xFF9B82, dark: 0xFF9B82)
    static let sage500 = primary
    static let olive700 = primaryPressed

    static let mint50 = adaptive(light: 0xF2F8F1, dark: 0x18261D)
    static let mint200 = adaptive(light: 0xD8EFD5, dark: 0x274731)

    static let accent = primary
    static let accentStrong = primaryPressed
    static let accentSoft = primarySoft
    static let point = warning
    static let line = divider
    static let secondaryText = textSecondary
    static let tertiaryText = textTertiary
    static let primaryText = textPrimary
    static let skeletonBase = gray100
    static let skeletonHighlight = adaptive(light: 0xFFFFFF, dark: 0x332B26).opacity(0.86)
    static let danger = error
    static let overlay = Color.black.opacity(0.18)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(
            uiColor: UIColor { traitCollection in
                UIColor(hex: traitCollection.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
