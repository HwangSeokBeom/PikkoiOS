import SwiftUI
import UIKit
import WebKit

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
        .navigationBarBackButtonHidden(
            presenter.viewState.showsCompletionView
                || presenter.viewState.paymentStage.blocksBackNavigation
        )
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
    let paymentGateway: any PaymentGateway
    let onResult: @MainActor (CheckoutPaymentBridgeResult) -> Void

    @State private var hasCompleted = false

    var body: some View {
        NavigationStack {
            PortOnePaymentWebView(
                context: context,
                paymentGateway: paymentGateway,
                onResult: sendGatewayResult(_:)
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("결제 진행")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        sendResult(.cancelled)
                    }
                }
            }
        }
    }

    private func sendGatewayResult(_ result: PaymentGatewayResult) {
        Logger.shared.debug(
            "PortOne payment callback orderCode=\(context.orderCode) success=\(result.success) impUidPresent=\(result.impUID?.isEmpty == false) merchantUid=\(result.merchantUID ?? "nil") errorCode=\(result.errorCode ?? "nil")"
        )
        if result.success {
            guard let impUID = result.impUID else {
                sendResult(.missingImpUID)
                return
            }
            sendResult(.succeeded(impUID: impUID, merchantUID: result.merchantUID))
            return
        }

        Logger.shared.debug(
            "PortOne payment callback failed orderCode=\(context.orderCode) errorCode=\(result.errorCode ?? "nil") message=\(result.errorMessage ?? "nil") raw=\(result.rawDescription ?? "nil")"
        )

        // Current server validation accepts imp_uid only. For success=false callbacks,
        // even if PortOne returns imp_uid, the default client policy is to keep the cart
        // and avoid server validation until the backend accepts success/error metadata.
        if isCancellation(result) {
            sendResult(.cancelled)
        } else {
            sendResult(.failed(message: friendlyFailureMessage(from: result)))
        }
    }

    private func sendResult(_ result: CheckoutPaymentBridgeResult) {
        guard !hasCompleted else { return }
        hasCompleted = true

        Task { @MainActor in
            onResult(result)
        }
    }

    private func isCancellation(_ result: PaymentGatewayResult) -> Bool {
        let combined = [
            result.errorCode,
            result.errorMessage,
            result.rawDescription
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return combined.contains("cancel") || combined.contains("취소")
    }

    private func friendlyFailureMessage(from result: PaymentGatewayResult) -> String {
        if let errorMessage = result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !errorMessage.isEmpty {
            return "결제를 완료하지 못했어요. \(errorMessage)"
        }

        return "결제를 완료하지 못했어요. 결제 수단 또는 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
    }
}

private struct PortOnePaymentWebView: UIViewControllerRepresentable {
    let context: CheckoutPaymentBridgeContext
    let paymentGateway: any PaymentGateway
    let onResult: @MainActor (PaymentGatewayResult) -> Void

    func makeUIViewController(context: Context) -> PortOnePaymentViewController {
        PortOnePaymentViewController(
            paymentContext: self.context,
            paymentGateway: paymentGateway,
            onResult: onResult
        )
    }

    func updateUIViewController(_ uiViewController: PortOnePaymentViewController, context: Context) {}
}

@MainActor
private final class PortOnePaymentViewController: UIViewController {
    private let paymentContext: CheckoutPaymentBridgeContext
    private let paymentGateway: any PaymentGateway
    private let onResult: @MainActor (PaymentGatewayResult) -> Void
    private let webView = WKWebView(frame: .zero)
    private var didStartPayment = false

    init(
        paymentContext: CheckoutPaymentBridgeContext,
        paymentGateway: any PaymentGateway,
        onResult: @escaping @MainActor (PaymentGatewayResult) -> Void
    ) {
        self.paymentContext = paymentContext
        self.paymentGateway = paymentGateway
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartPayment else { return }
        didStartPayment = true

        paymentGateway.requestPayment(
            on: webView,
            request: paymentContext.paymentRequest
        ) { [weak self] result in
            guard let self else { return }
            onResult(result)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        paymentGateway.close()
    }
}
