import SwiftUI

struct TagChip: View {
    enum Appearance {
        case filled
        case outlined
        case subtle
    }

    enum Size {
        case regular
        case compact
        case mini
    }

    let title: String
    var systemImage: String?
    var isSelected = false
    var appearance: Appearance = .outlined
    var action: (() -> Void)?
    var size: Size = .regular

    var body: some View {
        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private var label: some View {
        HStack(spacing: contentSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
            }
            Text(title)
                .font(font)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var foregroundColor: Color {
        if isSelected {
            return appearance == .filled ? .white : PikkoColor.accentStrong
        }
        return appearance == .subtle ? PikkoColor.secondaryText : PikkoColor.gray500
    }

    private var backgroundColor: Color {
        if isSelected {
            return appearance == .filled ? PikkoColor.accent : PikkoColor.surfaceMuted
        }

        switch appearance {
        case .filled:
            return PikkoColor.gray200
        case .outlined:
            return .white
        case .subtle:
            return PikkoColor.gray100
        }
    }

    private var borderColor: Color {
        if isSelected {
            return appearance == .filled ? .clear : PikkoColor.accent.opacity(0.55)
        }

        switch appearance {
        case .filled:
            return .clear
        case .outlined:
            return PikkoColor.gray200
        case .subtle:
            return .clear
        }
    }

    private var font: Font {
        switch size {
        case .regular:
            return PikkoTypography.captionStrong
        case .compact:
            return PikkoTypography.micro
        case .mini:
            return .system(size: 10, weight: .semibold)
        }
    }

    private var height: CGFloat {
        switch size {
        case .regular:
            return 36
        case .compact:
            return 30
        case .mini:
            return 24
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular:
            return PikkoSpacing.sm
        case .compact:
            return 10
        case .mini:
            return 8
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .regular:
            return PikkoRadius.chip
        case .compact:
            return 15
        case .mini:
            return 12
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .regular:
            return 11
        case .compact:
            return 10
        case .mini:
            return 9
        }
    }

    private var contentSpacing: CGFloat {
        switch size {
        case .regular:
            return 6
        case .compact:
            return 5
        case .mini:
            return 4
        }
    }
}

#Preview {
    HStack(spacing: PikkoSpacing.xs) {
        TagChip(title: "검색한 메뉴", systemImage: "magnifyingglass", isSelected: true)
        TagChip(title: "수제도넛", appearance: .outlined)
        TagChip(title: "픽업됨", systemImage: "takeoutbag.and.cup.and.straw.fill", isSelected: true, appearance: .filled)
    }
    .padding()
    .background(PikkoColor.background)
}
