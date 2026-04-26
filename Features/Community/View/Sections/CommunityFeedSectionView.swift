import SwiftUI

struct CommunityFeedSectionView: View {
    let banner: CommunityFeaturedBanner?
    let posts: [CommunityCard.Model]
    let selectedSortTitle: String
    let imageLoader: any AuthorizedImageLoading
    let onPostTap: (String) -> Void
    let onStoreSnippetTap: (String) -> Void
    let onPostAppear: (String) -> Void
    let onLikeTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
            SectionHeader(
                title: "타임라인",
                actionTitle: selectedSortTitle,
                actionSystemImage: "line.3.horizontal.decrease"
            )
            .padding(.horizontal, PikkoSpacing.xl)

            if let banner {
                CommunityHighlightBannerView(banner: banner)
            }

            Rectangle()
                .fill(PikkoColor.line)
                .frame(height: 1)
                .padding(.horizontal, PikkoSpacing.xl)

            LazyVStack(spacing: 0) {
                ForEach(posts) { post in
                    CommunityCard(
                        model: post,
                        loader: imageLoader,
                        onCardTapped: {
                            onPostTap(post.id)
                        },
                        onLikeTapped: {
                            onLikeTap(post.id)
                        },
                        onStoreSnippetTapped: { storeID in
                            onStoreSnippetTap(storeID)
                        }
                    )
                    .onAppear {
                        onPostAppear(post.id)
                    }
                }
            }
            .padding(.horizontal, PikkoSpacing.xl)
        }
    }
}

#Preview {
    CommunityFeedSectionView(
        banner: .init(
            eyebrow: "새싹멤버십 전용 사용 혜택",
            title: "피자부터 커피까지\n픽업하면 0원",
            badgeText: "SeSAC ONLY",
            pageText: "1 / 12",
            systemImage: "takeoutbag.and.cup.and.straw.fill"
        ),
        posts: [
            .init(
                id: "community-post-preview",
                authorName: "새싹 초로록 찹찹",
                authorAvatarPath: "community-avatar-preview",
                timeText: "51분 전",
                title: "입안에서 피어나는 봄, 도넛 한 입",
                bodyText: "가게 문을 열자마자 퍼지는 달콤한 향기와 포근한 맛이 하루를 천천히 풀어줬어요.",
                likeText: "12개",
                distanceText: "102M",
                media: [
                    .init(id: "a", path: "community-donut-video.mov"),
                    .init(id: "b", path: "community-donut-photo-a"),
                    .init(id: "c", path: "community-donut-photo-b")
                ],
                storeSnippet: .init(
                    id: "store-preview",
                    title: "새싹 도넛 가게",
                    subtitle: "디저트 · 서울 영등포구 선유로9길 30",
                    imagePath: "community-store-1"
                ),
                isLiked: false
            )
        ],
        selectedSortTitle: "최신순",
        imageLoader: PreviewAuthorizedImageLoader(),
        onPostTap: { _ in },
        onStoreSnippetTap: { _ in },
        onPostAppear: { _ in },
        onLikeTap: { _ in }
    )
    .background(PikkoColor.background)
}
