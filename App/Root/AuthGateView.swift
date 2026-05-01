import SwiftUI

struct AuthGateView: View {
    let featureBuilderFactory: FeatureBuilderFactory

    var body: some View {
        featureBuilderFactory.makeAuthView(context: .generic)
            .onAppear {
                Logger(category: "AuthGate").debug("[AuthGate] show reason=sessionMissing authState=unauthenticated")
            }
    }
}
