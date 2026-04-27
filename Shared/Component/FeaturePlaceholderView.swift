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

                PrimaryButton(title: primaryActionTitle, action: onPrimaryAction)
            }
            .padding(PikkoSpacing.xl)
        }
        .background(PikkoColor.background.ignoresSafeArea())
    }
}
