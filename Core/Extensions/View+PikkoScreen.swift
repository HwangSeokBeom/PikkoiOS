import SwiftUI

extension View {
    func pikkoScreen(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PikkoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(PikkoColor.primary)
    }
}
