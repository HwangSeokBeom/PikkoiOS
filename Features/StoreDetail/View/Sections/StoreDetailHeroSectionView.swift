import SwiftUI

struct StoreDetailHeroSectionView: View {
    let imagePaths: [String]
    let isLiked: Bool
    let imageLoader: any AuthorizedImageLoading
    let onBackTap: () -> Void
    let onLikeTap: () -> Void

    @State private var selectedIndex = 0

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(imagePaths.enumerated()), id: \.offset) { index, path in
                    AuthorizedAsyncImage(
                        path: path,
                        loader: imageLoader,
                        contentMode: .fill,
                        cornerRadius: 0,
                        showsProgress: false
                    )
                    .tag(index)
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.18)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 330)

            HStack {
                circleButton(systemImage: "chevron.left", action: onBackTap)
                Spacer()
                circleButton(systemImage: isLiked ? "heart.fill" : "heart", action: onLikeTap)
            }
            .padding(.horizontal, PikkoSpacing.lg)
            .padding(.top, 58)
        }
        .frame(height: 330)
        .background(PikkoColor.surfaceMuted)
    }

    private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.22))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
