import SwiftUI

extension View {
    func pikkoScreen(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
