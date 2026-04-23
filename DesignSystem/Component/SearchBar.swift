import SwiftUI

struct SearchBar: View {
    @Binding var text: String

    var placeholder = "검색어를 입력해주세요."
    var accessorySystemImage: String?
    var onAccessoryTap: (() -> Void)?
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: PikkoSpacing.sm) {
            HStack(spacing: PikkoSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PikkoColor.sage500)
                TextField(placeholder, text: $text)
                    .font(PikkoTypography.body)
                    .foregroundStyle(PikkoColor.primaryText)
                    .submitLabel(.search)
                    .onSubmit {
                        onSubmit?()
                    }
            }
            .padding(.horizontal, PikkoSpacing.md)
            .frame(height: 48)
            .background(.white)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.floatingCTA, style: .continuous)
                    .stroke(PikkoColor.accent.opacity(0.35), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.floatingCTA, style: .continuous))

            if let accessorySystemImage, let onAccessoryTap {
                Button(action: onAccessoryTap) {
                    Image(systemName: accessorySystemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(PikkoColor.sage300)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
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
