import SwiftUI

struct TagChip: View {
    enum Appearance {
        case filled
        case outlined
        case subtle
    }

    let title: String
    var systemImage: String?
    var isSelected = false
    var appearance: Appearance = .outlined
    var action: (() -> Void)?

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
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(PikkoTypography.captionStrong)
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, PikkoSpacing.sm)
        .frame(height: 36)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: PikkoRadius.chip, style: .continuous)
                .stroke(borderColor, lineWidth: borderColor == .clear ? 0 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.chip, style: .continuous))
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
