import SwiftUI
import WebKit

struct HomeRootView: View {
    @StateObject private var presenter: HomePresenter
    @StateObject private var router: HomeRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeStoreDetailView: (String) -> StoreDetailRootView
    private let makeStoreSearchView: (String) -> AnyView
    private let makeBannerWebView: (HomeBannerItem) -> AnyView
    private let makeAuthView: () -> AnyView

    @State private var presentedStoreID: String?
    @State private var presentedSearchQuery: String?
    @State private var presentedBanner: HomeBannerItem?

    init(
        presenter: HomePresenter,
        router: HomeRouter,
        imageLoader: any AuthorizedImageLoading,
        makeStoreDetailView: @escaping (String) -> StoreDetailRootView,
        makeStoreSearchView: @escaping (String) -> AnyView,
        makeBannerWebView: @escaping (HomeBannerItem) -> AnyView,
        makeAuthView: @escaping () -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeStoreDetailView = makeStoreDetailView
        self.makeStoreSearchView = makeStoreSearchView
        self.makeBannerWebView = makeBannerWebView
        self.makeAuthView = makeAuthView
    }

    var body: some View {
        HomeView(
            presenter: presenter,
            imageLoader: imageLoader,
            onAuthTap: {
                Task { await presenter.send(.loginRequiredTapped) }
            }
        )
        .task {
            await presenter.send(.onAppear)
        }
        .onChange(of: router.pendingDestination) { _, destination in
            switch destination {
            case .storeDetail(let storeID):
                presentedStoreID = storeID
            case .search(let query):
                presentedSearchQuery = query
            case .bannerWeb(let banner):
                presentedBanner = banner
            case .none:
                break
            }
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            }
        }
        .navigationDestination(isPresented: searchPresentedBinding) {
            if let presentedSearchQuery {
                makeStoreSearchView(presentedSearchQuery)
            }
        }
        .navigationDestination(isPresented: bannerPresentedBinding) {
            if let presentedBanner {
                makeBannerWebView(presentedBanner)
            }
        }
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView()
        }
    }

    private var storeDetailPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedStoreID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedStoreID = nil
                    router.clearPendingRoute()
                }
            }
        )
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

    private var searchPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedSearchQuery != nil },
            set: { isPresented in
                if !isPresented {
                    presentedSearchQuery = nil
                    router.clearPendingRoute()
                }
            }
        )
    }

    private var bannerPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedBanner != nil },
            set: { isPresented in
                if !isPresented {
                    presentedBanner = nil
                    router.clearPendingRoute()
                }
            }
        )
    }
}

struct PikkoWebContentView: View {
    let title: String
    let requestLoader: @Sendable () async throws -> URLRequest
    var onURLChange: @Sendable (URL) -> Void = { _ in }
    var onNavigationError: @Sendable (String) -> Void = { _ in }
    var onClose: (() -> Void)? = nil

    @State private var request: URLRequest?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()
                    LoadingView(message: "\(title) 로딩 중")
                        .padding(PikkoSpacing.xl)
                }
            } else if let request {
                PikkoWebViewRepresentable(
                    request: request,
                    onURLChange: onURLChange,
                    onNavigationError: { error in
                        let message = error.localizedDescription
                        Task { @MainActor in
                            errorMessage = message
                            onNavigationError(message)
                        }
                    }
                )
                .overlay(alignment: .bottom) {
                    if let errorMessage {
                        ToastView(message: errorMessage, tone: .warning)
                            .padding(PikkoSpacing.lg)
                    }
                }
            } else {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    EmptyStateView(
                        title: "\(title)을(를) 열지 못했어요",
                        message: errorMessage ?? "잠시 후 다시 시도해 주세요.",
                        actionTitle: "다시 시도하기",
                        action: {
                            Task {
                                await loadRequest()
                            }
                        }
                    )
                    .padding(PikkoSpacing.xl)
                }
            }
        }
        .task {
            guard request == nil else { return }
            await loadRequest()
        }
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기", action: onClose)
                }
            }
        }
        .pikkoScreen(title: title)
    }

    private func loadRequest() async {
        isLoading = true
        errorMessage = nil

        do {
            request = try await requestLoader()
        } catch {
            request = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct PikkoWebViewRepresentable: UIViewRepresentable {
    let request: URLRequest
    let onURLChange: @Sendable (URL) -> Void
    let onNavigationError: @Sendable (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onURLChange: onURLChange,
            onNavigationError: onNavigationError
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .clear
        webView.isOpaque = false
        context.coordinator.loadedRequestKey = requestKey(for: request)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let key = requestKey(for: request)
        guard context.coordinator.loadedRequestKey != key else { return }
        context.coordinator.loadedRequestKey = key
        uiView.load(request)
    }

    private func requestKey(for request: URLRequest) -> String {
        let url = request.url?.absoluteString ?? "missing-url"
        return "\(request.httpMethod ?? "GET"):\(url)"
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onURLChange: @Sendable (URL) -> Void
        let onNavigationError: @Sendable (Error) -> Void
        var loadedRequestKey: String?

        init(
            onURLChange: @escaping @Sendable (URL) -> Void,
            onNavigationError: @escaping @Sendable (Error) -> Void
        ) {
            self.onURLChange = onURLChange
            self.onNavigationError = onNavigationError
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                onURLChange(url)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                onURLChange(url)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            onNavigationError(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onNavigationError(error)
        }
    }
}
