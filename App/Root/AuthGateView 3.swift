import SwiftUI

struct AuthGateView: View {
    let featureBuilderFactory: FeatureBuilderFactory
    @State private var isAuthFlowPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                heroSection
                lockedExperienceCard

                VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                    Text("로그인 후 이용할 수 있어요")
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(PikkoColor.primaryText)

                    Text("주문 추적, 커뮤니티 활동, 인증 이미지가 필요한 가게 정보는 로그인 이후 진입을 기본값으로 둡니다.")
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineSpacing(4)
                }

                PrimaryButton(title: "로그인하고 시작하기") {
                    isAuthFlowPresented = true
                }
            }
            .padding(.horizontal, PikkoSpacing.xl)
            .padding(.top, PikkoSpacing.xxl)
            .padding(.bottom, PikkoSpacing.xxl)
        }
        .background(PikkoColor.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $isAuthFlowPresented) {
            NavigationStack {
                featureBuilderFactory.makeAuthView()
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            Text("Pikko")
                .font(PikkoTypography.hero)
                .foregroundStyle(PikkoColor.accentStrong)

            Text("주문과 픽업 흐름은 로그인 이후부터 자연스럽게 이어집니다.")
                .font(PikkoTypography.title)
                .foregroundStyle(PikkoColor.primaryText)
                .lineSpacing(4)

            HStack(spacing: PikkoSpacing.xs) {
                TagChip(title: "픽업 추적", systemImage: "figure.walk", isSelected: true, appearance: .filled)
                TagChip(title: "주문 현황", systemImage: "list.clipboard", appearance: .outlined)
                TagChip(title: "커뮤니티", systemImage: "person.3", appearance: .outlined)
            }
        }
    }

    private var lockedExperienceCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
            HStack(alignment: .top, spacing: PikkoSpacing.md) {
                authIcon

                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text("로그인 게이트")
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(PikkoColor.primaryText)

                    Text("루트 셸은 인증 상태를 기준으로 분기하고, 실제 Auth Feature는 별도 흐름으로 유지합니다.")
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                        .lineSpacing(4)
                }
            }

            VStack(spacing: PikkoSpacing.sm) {
                gateRow(
                    title: "홈 / 주문 / 커뮤니티 / 프로필 탭",
                    subtitle: "로그인 이후 서버 연동 진입",
                    systemImage: "square.grid.2x2.fill"
                )
                gateRow(
                    title: "장바구니 퀵 액션",
                    subtitle: "쉘 오버레이로 유지",
                    systemImage: "sparkles"
                )
                gateRow(
                    title: "인증 이미지 자원",
                    subtitle: "기존 authorized image loader 재사용",
                    systemImage: "photo.on.rectangle"
                )
            }
        }
        .padding(PikkoSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PikkoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.sheet, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var authIcon: some View {
        Circle()
            .fill(PikkoColor.accentSoft)
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PikkoColor.accentStrong)
            }
    }

    private func gateRow(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: PikkoSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PikkoColor.accentStrong)
                .frame(width: 28, height: 28)
                .background(PikkoColor.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PikkoTypography.bodyStrong)
                    .foregroundStyle(PikkoColor.primaryText)
                Text(subtitle)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
            }

            Spacer()
        }
    }
}
