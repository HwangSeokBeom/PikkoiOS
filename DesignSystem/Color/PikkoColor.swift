import SwiftUI

enum PikkoColor {
    static let sage50 = Color(red: 0.95, green: 0.97, blue: 0.93)
    static let sage100 = Color(red: 0.88, green: 0.92, blue: 0.85)
    static let sage300 = Color(red: 0.71, green: 0.78, blue: 0.64)
    static let sage500 = Color(red: 0.56, green: 0.65, blue: 0.49)
    static let olive700 = Color(red: 0.35, green: 0.42, blue: 0.28)

    static let mint50 = Color(red: 0.92, green: 0.97, blue: 0.95)
    static let mint200 = Color(red: 0.76, green: 0.88, blue: 0.83)

    static let warmWhite = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let warmYellow = Color(red: 0.98, green: 0.78, blue: 0.20)
    static let coralHeart = Color(red: 0.93, green: 0.69, blue: 0.35)

    static let ink900 = Color(red: 0.22, green: 0.23, blue: 0.24)
    static let gray100 = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let gray200 = Color(red: 0.91, green: 0.91, blue: 0.89)
    static let gray300 = Color(red: 0.83, green: 0.83, blue: 0.80)
    static let gray400 = Color(red: 0.69, green: 0.70, blue: 0.67)
    static let gray500 = Color(red: 0.53, green: 0.54, blue: 0.52)
    static let gray600 = Color(red: 0.42, green: 0.43, blue: 0.41)

    static let background: Color = warmWhite
    static let surface: Color = .white
    static let surfaceMuted: Color = sage50
    static let surfaceElevated: Color = Color.white.opacity(0.95)
    static let accent: Color = sage500
    static let accentStrong: Color = olive700
    static let accentSoft: Color = sage100
    static let point: Color = warmYellow
    static let line: Color = gray200
    static let divider: Color = gray100
    static let secondaryText: Color = gray500
    static let tertiaryText: Color = gray400
    static let primaryText: Color = ink900
    static let skeletonBase: Color = gray100
    static let skeletonHighlight: Color = Color.white.opacity(0.85)
    static let danger: Color = Color(red: 0.83, green: 0.36, blue: 0.36)
    static let success: Color = sage500
    static let overlay: Color = Color.black.opacity(0.12)
}
