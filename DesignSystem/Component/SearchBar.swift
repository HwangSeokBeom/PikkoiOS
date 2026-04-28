import SwiftUI

struct SearchBar: View {
    enum Style {
        case regular
        case compact
    }

    @Binding var text: String

    var placeholder = "검색어를 입력해주세요."
    var accessorySystemImage: String?
    var onAccessoryTap: (() -> Void)?
    var onSubmit: (() -> Void)?
    var showsSearchAction = false
    var onClearTap: (() -> Void)?
    var style: Style = .regular

    var body: some View {
        HStack(spacing: interItemSpacing) {
            HStack(spacing: iconSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(iconColor)

                TextField(
                    "",
                    text: $text,
                    prompt: Text(placeholder)
                        .foregroundStyle(placeholderColor)
                )
                    .font(textFont)
                    .foregroundStyle(PikkoColor.primaryText)
                    .submitLabel(.search)
                    .onSubmit {
                        onSubmit?()
                    }

                if !text.isEmpty {
                    Button {
                        text = ""
                        onClearTap?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PikkoColor.gray400)
                    }
                    .buttonStyle(.plain)
                }

                if showsSearchAction {
                    Button {
                        onSubmit?()
                    } label: {
                        Text("검색")
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(PikkoColor.accent)
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: fieldHeight)
            .background(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if let accessorySystemImage, let onAccessoryTap {
                Button(action: onAccessoryTap) {
                    Image(systemName: accessorySystemImage)
                        .font(.system(size: accessoryIconSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: fieldHeight, height: fieldHeight)
                        .background(PikkoColor.sage300)
                        .clipShape(RoundedRectangle(cornerRadius: accessoryCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fieldHeight: CGFloat {
        switch style {
        case .regular:
            return 48
        case .compact:
            return 42
        }
    }

    private var cornerRadius: CGFloat {
        fieldHeight / 2
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .regular:
            return PikkoSpacing.md
        case .compact:
            return 14
        }
    }

    private var textFont: Font {
        switch style {
        case .regular:
            return PikkoTypography.body
        case .compact:
            return PikkoTypography.subheadline
        }
    }

    private var iconColor: Color {
        switch style {
        case .regular:
            return PikkoColor.sage500
        case .compact:
            return PikkoColor.sage300
        }
    }

    private var placeholderColor: Color {
        switch style {
        case .regular:
            return PikkoColor.gray400
        case .compact:
            return PikkoColor.gray500
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .regular:
            return .white
        case .compact:
            return PikkoColor.surface
        }
    }

    private var borderColor: Color {
        switch style {
        case .regular:
            return PikkoColor.accent.opacity(0.35)
        case .compact:
            return PikkoColor.gray200
        }
    }

    private var interItemSpacing: CGFloat {
        switch style {
        case .regular:
            return PikkoSpacing.sm
        case .compact:
            return PikkoSpacing.xs
        }
    }

    private var iconSpacing: CGFloat {
        switch style {
        case .regular:
            return PikkoSpacing.xs
        case .compact:
            return 6
        }
    }

    private var iconSize: CGFloat {
        switch style {
        case .regular:
            return 16
        case .compact:
            return 15
        }
    }

    private var accessoryIconSize: CGFloat {
        switch style {
        case .regular:
            return 18
        case .compact:
            return 16
        }
    }

    private var accessoryCornerRadius: CGFloat {
        switch style {
        case .regular:
            return 12
        case .compact:
            return 10
        }
    }
}

#Preview {
    StatefulPreviewWrapper("") { text in
        SearchBar(
            text: text,
            accessorySystemImage: "slider.horizontal.3",
            onAccessoryTap: {}
        )
        .padding()
        .background(PikkoColor.background)
    }
}
