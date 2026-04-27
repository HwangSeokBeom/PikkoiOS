import SwiftUI

struct StoreDetailReviewSummarySectionView: View {
    let ratingSummary: StoreDetailRatingSummary
    let reviewPreview: StoreDetailReviewPreview
    let ratingBars: [StoreDetailReviewRatingBar]
    var onWriteTapped: (() -> Void)?
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            SectionHeader(
                title: "리뷰 요약",
                subtitle: reviewPreview.metricSummary,
                actionTitle: reviewPreview.showsActions ? nil : "리뷰 작성",
                actionSystemImage: reviewPreview.showsActions ? nil : "star.bubble.fill",
                action: reviewPreview.showsActions ? nil : onWriteTapped
            )

            VStack(alignment: .leading, spacing: PikkoSpacing.md) {
                HStack(spacing: PikkoSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ratingSummary.ratingText)
                            .font(PikkoTypography.hero)
                            .foregroundStyle(PikkoColor.primaryText)
                        RatingSummaryView(
                            ratingText: ratingSummary.ratingText,
                            reviewCountText: ratingSummary.reviewCountText
                        )
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        reviewMetric(label: "찜 수", value: ratingSummary.likeCountText)
                        reviewMetric(label: "누적 주문", value: ratingSummary.orderCountText)
                    }
                }

                VStack(spacing: PikkoSpacing.xs) {
                    ForEach(ratingBars) { ratingBar in
                        HStack(spacing: PikkoSpacing.sm) {
                            Text("\(ratingBar.rating)")
                                .font(PikkoTypography.captionStrong)
                                .foregroundStyle(PikkoColor.primaryText)
                                .frame(width: 12, alignment: .leading)

                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(PikkoColor.surfaceMuted)

                                    Capsule()
                                        .fill(PikkoColor.sage300)
                                        .frame(width: proxy.size.width * ratingBar.ratio)
                                }
                            }
                            .frame(height: 8)

                            Text("\(ratingBar.count)")
                                .font(PikkoTypography.caption)
                                .foregroundStyle(PikkoColor.secondaryText)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                    HStack(alignment: .top) {
                        Text(reviewPreview.title)
                            .font(PikkoTypography.cardTitle)
                            .foregroundStyle(PikkoColor.primaryText)

                        Spacer()

                        if reviewPreview.showsActions {
                            Menu {
                                Button {
                                    onEditTapped?()
                                } label: {
                                    Label("수정", systemImage: "square.and.pencil")
                                }

                                Button(role: .destructive) {
                                    isDeleteConfirmationPresented = true
                                } label: {
                                    Label("삭제", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(PikkoColor.secondaryText)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }

                    Text(reviewPreview.body)
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineSpacing(4)

                    HStack(spacing: PikkoSpacing.xs) {
                        ForEach(reviewPreview.keywordBadges, id: \.self) { badge in
                            TagChip(title: badge, appearance: .subtle)
                        }
                    }

                    Text(reviewPreview.authorName)
                        .font(PikkoTypography.captionStrong)
                        .foregroundStyle(PikkoColor.accentStrong)

                    Text("별점 \(reviewPreview.ratingText)")
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }
            }
            .padding(PikkoSpacing.lg)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
            .pikkoShadow(PikkoShadow.card)
        }
        .confirmationDialog("리뷰를 삭제할까요?", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                onDeleteTapped?()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 리뷰는 복구할 수 없어요.")
        }
    }

    private func reviewMetric(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
            Spacer()
            Text(value)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.primaryText)
        }
    }
}
