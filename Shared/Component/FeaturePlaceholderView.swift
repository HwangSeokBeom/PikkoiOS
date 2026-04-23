import SwiftUI

struct FeaturePlaceholderView: View {
    let title: String
    let subtitle: String
    let primaryActionTitle: String
    let onPrimaryAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text(title)
                        .font(PikkoTypography.hero)
                        .foregroundStyle(PikkoColor.primaryText)
                    Text(subtitle)
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.secondaryText)
                }

                VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                    Text("Scaffold Notes")
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(PikkoColor.primaryText)
                    Text("This screen is intentionally shallow. Presenter, Interactor, and Router are wired so the feature can expand without root-level rewrites.")
                        .foregroundStyle(PikkoColor.secondaryText)
                        .font(PikkoTypography.body)
                }
                .padding(PikkoSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PikkoColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
                .pikkoShadow(PikkoShadow.card)

                PrimaryButton(title: primaryActionTitle, action: onPrimaryAction)
            }
            .padding(PikkoSpacing.xl)
        }
        .background(PikkoColor.background.ignoresSafeArea())
    }
}
