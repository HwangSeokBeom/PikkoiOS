import SwiftUI
import MapKit
import UIKit
import WebKit

struct HomeRootView: View {
    @StateObject private var presenter: HomePresenter
    @StateObject private var router: HomeRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeStoreDetailView: (String) -> StoreDetailRootView
    private let makeStoreSearchView: (String) -> AnyView
    private let makeBannerWebView: (HomeBannerItem) -> AnyView
    private let makeNotificationListView: () -> AnyView
    private let makeCartView: () -> CartRootView
    private let makeAuthView: () -> AnyView
    private let resetTrigger: Int

    @State private var presentedStoreID: String?
    @State private var presentedSearchQuery: String?
    @State private var presentedBanner: HomeBannerItem?
    @State private var isNotificationListPresented = false
    @State private var isCartPresented = false
    @State private var isLocationSearchPresented = false
    @Environment(\.openURL) private var openURL

    init(
        presenter: HomePresenter,
        router: HomeRouter,
        imageLoader: any AuthorizedImageLoading,
        makeStoreDetailView: @escaping (String) -> StoreDetailRootView,
        makeStoreSearchView: @escaping (String) -> AnyView,
        makeBannerWebView: @escaping (HomeBannerItem) -> AnyView,
        makeNotificationListView: @escaping () -> AnyView,
        makeCartView: @escaping () -> CartRootView,
        makeAuthView: @escaping () -> AnyView,
        resetTrigger: Int = 0
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeStoreDetailView = makeStoreDetailView
        self.makeStoreSearchView = makeStoreSearchView
        self.makeBannerWebView = makeBannerWebView
        self.makeNotificationListView = makeNotificationListView
        self.makeCartView = makeCartView
        self.makeAuthView = makeAuthView
        self.resetTrigger = resetTrigger
    }

    var body: some View {
        HomeView(
            presenter: presenter,
            imageLoader: imageLoader,
            onAuthTap: {
                Task { await presenter.send(.loginRequiredTapped) }
            },
            onCartTap: {
                isCartPresented = true
            },
            resetTrigger: resetTrigger
        )
        .task {
            await presenter.send(.onAppear)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pikkoSelectedLocationDidChange)) { _ in
            Task { await presenter.send(.refreshRequested) }
        }
        .onChange(of: router.pendingDestination) { _, destination in
            switch destination {
            case .storeDetail(let storeID):
                presentedStoreID = storeID
            case .search(let query):
                presentedSearchQuery = query
            case .bannerWeb(let banner):
                presentedBanner = banner
            case .notificationList:
                isNotificationListPresented = true
            case .locationSearch:
                isLocationSearchPresented = true
            case .none:
                break
            }
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: searchPresentedBinding) {
            if let presentedSearchQuery {
                makeStoreSearchView(presentedSearchQuery)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: bannerPresentedBinding) {
            if let presentedBanner {
                makeBannerWebView(presentedBanner)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: notificationListPresentedBinding) {
            makeNotificationListView()
        }
        .sheet(isPresented: $isCartPresented) {
            NavigationStack {
                makeCartView()
            }
        }
        .navigationDestination(isPresented: locationSearchPresentedBinding) {
            LocationSearchView(
                onCurrentLocationTap: {
                    isLocationSearchPresented = false
                    router.clearPendingRoute()
                    Task { await presenter.send(.currentLocationRequested) }
                },
                onLocationSelected: { location in
                    isLocationSearchPresented = false
                    router.clearPendingRoute()
                    Task { await presenter.send(.selectedLocationSelected(location)) }
                }
            )
        }
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView()
        }
        .confirmationDialog(
            "위치 설정",
            isPresented: locationPickerPresentedBinding,
            titleVisibility: .visible
        ) {
            Button("현재 위치 사용") {
                Task { await presenter.send(.currentLocationRequested) }
            }
            Button("지역 검색") {
                Task { await presenter.send(.manualLocationSelectionTapped) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 위치 주변의 가게를 다시 불러올 수 있어요.")
        }
        .alert("위치 권한이 필요해요", isPresented: locationPermissionSettingsPresentedBinding) {
            Button("설정 열기") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(settingsURL)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 위치 주변의 가게를 보려면 설정에서 위치 접근을 허용해 주세요.")
        }
        .onChange(of: resetTrigger) { _, _ in
            presentedStoreID = nil
            presentedSearchQuery = nil
            presentedBanner = nil
            isNotificationListPresented = false
            isCartPresented = false
            isLocationSearchPresented = false
            router.clearPendingRoute()
            Task { await presenter.send(.notificationUnreadCountReloadRequested) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pikkoAppNotificationUnreadCountDidChange)) { notification in
            let count = notification.userInfo?[AppNotificationUserInfoKey.unreadCount] as? Int ?? 0
            Task { await presenter.send(.notificationUnreadCountChanged(count)) }
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

    private var notificationListPresentedBinding: Binding<Bool> {
        Binding(
            get: { isNotificationListPresented },
            set: { isPresented in
                if !isPresented {
                    isNotificationListPresented = false
                    router.clearPendingRoute()
                    Task { await presenter.send(.notificationUnreadCountReloadRequested) }
                }
            }
        )
    }

    private var locationSearchPresentedBinding: Binding<Bool> {
        Binding(
            get: { isLocationSearchPresented },
            set: { isPresented in
                if !isPresented {
                    isLocationSearchPresented = false
                    router.clearPendingRoute()
                }
            }
        )
    }

    private var locationPickerPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.isLocationPickerPresented },
            set: { isPresented in
                if !isPresented {
                    router.dismissLocationPicker()
                }
            }
        )
    }

    private var locationPermissionSettingsPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.isLocationPermissionSettingsPresented },
            set: { isPresented in
                if !isPresented {
                    router.dismissLocationPermissionSettings()
                }
            }
        )
    }
}

private struct LocationSearchView: View {
    let onCurrentLocationTap: () -> Void
    let onLocationSelected: (PikkoSelectedLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PikkoSelectedLocation] = []
    @State private var isSearching = false
    @State private var emptyTitle: String?
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            PikkoColor.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                SearchBar(
                    text: $query,
                    placeholder: "지역이나 주소를 검색해주세요.",
                    onSubmit: {
                        Task { await search() }
                    },
                    style: .compact
                )

                Button(action: onCurrentLocationTap) {
                    HStack(spacing: PikkoSpacing.sm) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("현재 위치 사용")
                            .font(PikkoTypography.bodyStrong)
                        Spacer()
                    }
                    .foregroundStyle(PikkoColor.accentStrong)
                    .padding(PikkoSpacing.md)
                    .background(PikkoColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                }
                .buttonStyle(.plain)

                if isSearching {
                    LoadingView(message: "주소를 찾고 있어요")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message, results.isEmpty {
                    EmptyStateView(
                        title: emptyTitle ?? "검색 결과가 없어요",
                        message: message,
                        systemImage: "mappin.slash"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: PikkoSpacing.sm) {
                            ForEach(results) { result in
                                Button {
                                    onLocationSelected(result)
                                } label: {
                                    HStack(alignment: .top, spacing: PikkoSpacing.sm) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(PikkoColor.accent)
                                            .padding(.top, 2)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.title)
                                                .font(PikkoTypography.bodyStrong)
                                                .foregroundStyle(PikkoColor.primaryText)
                                                .lineLimit(2)

                                            if let subtitle = result.subtitle, !subtitle.isEmpty {
                                                Text(subtitle)
                                                    .font(PikkoTypography.caption)
                                                    .foregroundStyle(PikkoColor.secondaryText)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer(minLength: 0)
                                    }
                                    .padding(PikkoSpacing.md)
                                    .background(PikkoColor.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, RootTabBarMetrics.scrollContentBottomInset)
                    }
                }
            }
            .padding(PikkoSpacing.xl)
        }
        .navigationTitle("위치 선택")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("닫기") {
                    dismiss()
                }
            }
        }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                isSearching = false
                results = []
                emptyTitle = nil
                message = nil
                return
            }

            searchTask = Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                await search(term: trimmed)
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            emptyTitle = "검색어가 필요해요"
            message = "검색어를 입력한 뒤 다시 시도해 주세요."
            return
        }

        await search(term: trimmed)
    }

    private func search(term trimmed: String) async {
        isSearching = true
        emptyTitle = nil
        message = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = searchRegion()

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                isSearching = false
                return
            }
            results = response.mapItems.prefix(20).map { item in
                PikkoSelectedLocation(
                    title: item.name ?? item.placemark.locality ?? trimmed,
                    subtitle: makeSubtitle(from: item.placemark),
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude,
                    source: "mkLocalSearch"
                )
            }
            emptyTitle = results.isEmpty ? "검색 결과가 없어요" : nil
            message = results.isEmpty ? "다른 지역명이나 도로명 주소로 검색해 주세요." : nil
        } catch {
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                isSearching = false
                return
            }
            results = []
            emptyTitle = "주소 검색을 완료하지 못했어요"
            message = "주소 검색을 완료하지 못했어요. 잠시 후 다시 시도해 주세요."
        }

        isSearching = false
    }

    private func searchRegion() -> MKCoordinateRegion {
        if let location = SelectedLocationStore.shared.selectedLocation {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
            )
        }

        return LocationDefaults.searchRegion
    }

    private func makeSubtitle(from placemark: MKPlacemark) -> String? {
        [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
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
