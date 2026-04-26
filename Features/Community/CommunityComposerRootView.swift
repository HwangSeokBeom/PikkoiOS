import SwiftUI

struct CommunityComposerRootView: View {
    @StateObject private var presenter: CommunityComposerPresenter
    @StateObject private var router: CommunityComposerRouter
    private let onSubmittedPost: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        presenter: CommunityComposerPresenter,
        router: CommunityComposerRouter,
        onSubmittedPost: @escaping (String) -> Void = { _ in }
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.onSubmittedPost = onSubmittedPost
    }

    var body: some View {
        CommunityComposerView(presenter: presenter)
            .onChange(of: router.pendingRoute) { _, route in
                guard case let .communityDetail(postID) = route else { return }
                router.clearPendingRoute()
                dismiss()
                DispatchQueue.main.async {
                    onSubmittedPost(postID)
                }
            }
            .task {
                await presenter.send(.onAppear)
            }
    }
}
