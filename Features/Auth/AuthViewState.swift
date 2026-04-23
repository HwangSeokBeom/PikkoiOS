import Foundation

struct AuthViewState: Equatable {
    var title = "Welcome to Pikko"
    var subtitle = "The unauthenticated flow lands here first. Replace the stub sign-in with the real auth funnel later."
    var isLoading = false

    var primaryActionTitle: String {
        isLoading ? "Signing In..." : "Enter With Stub Session"
    }
}
