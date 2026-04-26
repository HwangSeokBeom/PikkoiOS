import SwiftUI

struct CheckoutRootView: View {
    @StateObject private var presenter: CheckoutPresenter
    @StateObject private var router: CheckoutRouter
    private let makeAuthView: () -> AnyView
    private let makeOrderView: (String?) -> OrderRootView
    private let makePaymentBridgeView: (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView

    init(
        presenter: CheckoutPresenter,
        router: CheckoutRouter,
        makeAuthView: @escaping () -> AnyView,
        makeOrderView: @escaping (String?) -> OrderRootView,
        makePaymentBridgeView: @escaping (CheckoutPaymentBridgeContext, @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.makeAuthView = makeAuthView
        self.makeOrderView = makeOrderView
        self.makePaymentBridgeView = makePaymentBridgeView
    }

    var body: some View {
        Group {
            if presenter.viewState.showsCompletionView {
                CheckoutSuccessView(presenter: presenter)
            } else {
                CheckoutView(presenter: presenter)
            }
        }
        .navigationBarBackButtonHidden(presenter.viewState.createdOrderID != nil)
        .navigationDestination(
            isPresented: Binding(
                get: {
                    if case .some(.orderHistory) = router.pendingRoute {
                        return true
                    }
                    return false
                },
                set: { isPresented in
                    if !isPresented {
                        router.clearPendingRoute()
                    }
                }
            )
        ) {
            makeOrderView(orderHistoryRouteID)
        }
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView()
        }
        .sheet(
            isPresented: paymentBridgePresentedBinding,
            onDismiss: {}
        ) {
            if let paymentContext = presenter.viewState.paymentBridgeContext {
                makePaymentBridgeView(
                    paymentContext,
                    { result in
                        Task { await presenter.send(.paymentBridgeResult(result)) }
                    }
                )
            }
        }
        .task {
            await presenter.send(.onAppear)
        }
    }

    private var orderHistoryRouteID: String? {
        guard case .some(.orderHistory(let orderID)) = router.pendingRoute else {
            return nil
        }
        return orderID
    }

    private var authPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.isAuthPresented },
            set: { isPresented in
                if !isPresented {
                    router.dismissAuth()
                }
            }
        )
    }

    private var paymentBridgePresentedBinding: Binding<Bool> {
        Binding(
            get: { presenter.viewState.paymentBridgeContext != nil },
            set: { isPresented in
                if !isPresented {
                    Task { await presenter.send(.paymentBridgeDismissed) }
                }
            }
        )
    }
}

struct CheckoutPaymentBridgeView: View {
    let context: CheckoutPaymentBridgeContext
    let requestLoader: @Sendable () async throws -> URLRequest
    let onResult: @MainActor (CheckoutPaymentBridgeResult) -> Void

    @State private var hasCompleted = false

    var body: some View {
        NavigationStack {
            PikkoWebContentView(
                title: "결제 진행",
                requestLoader: requestLoader,
                onURLChange: { url in
                    Task { @MainActor in
                        handle(url: url)
                    }
                },
                onNavigationError: { message in
                    Task { @MainActor in
                        sendResult(.failed(message: "결제 창을 불러오지 못했어요. \(message)"))
                    }
                },
                onClose: {
                    sendResult(.cancelled)
                }
            )
        }
    }

    private func handle(url: URL) {
        guard !hasCompleted else { return }

        if let impUID = extractValue(named: "imp_uid", from: url) {
            sendResult(.succeeded(impUID: impUID))
            return
        }

        if let redirectURL = context.redirectURL,
           matchesRedirect(url, redirectURL: redirectURL) {
            if let failureMessage = extractFailureMessage(from: url) {
                sendResult(.failed(message: failureMessage))
            } else {
                sendResult(.missingImpUID)
            }
            return
        }

        if let failureMessage = extractFailureMessage(from: url) {
            sendResult(.failed(message: failureMessage))
        }
    }

    private func sendResult(_ result: CheckoutPaymentBridgeResult) {
        guard !hasCompleted else { return }
        hasCompleted = true

        Task { @MainActor in
            onResult(result)
        }
    }

    private func matchesRedirect(_ currentURL: URL, redirectURL: URL) -> Bool {
        guard let currentComponents = URLComponents(url: currentURL, resolvingAgainstBaseURL: false),
              let redirectComponents = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false) else {
            return false
        }

        return currentComponents.scheme == redirectComponents.scheme
            && currentComponents.host == redirectComponents.host
            && currentComponents.path == redirectComponents.path
    }

    private func extractFailureMessage(from url: URL) -> String? {
        for key in ["error_msg", "error_message", "message", "msg"] {
            if let value = extractValue(named: key, from: url) {
                return "결제를 완료하지 못했어요. \(value)"
            }
        }
        return nil
    }

    private func extractValue(named name: String, from url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let value = components.queryItems?.first(where: { $0.name == name })?.value,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        guard let fragment = url.fragment, !fragment.isEmpty else {
            return nil
        }

        let prefixedFragment = fragment.hasPrefix("?") ? String(fragment.dropFirst()) : fragment
        let fragmentURL = URL(string: "https://fragment.local?\(prefixedFragment)")
        let fragmentComponents = fragmentURL.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }

        return fragmentComponents?.queryItems?.first(where: { $0.name == name })?.value
    }
}
