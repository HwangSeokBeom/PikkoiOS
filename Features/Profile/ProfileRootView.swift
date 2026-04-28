import AVKit
import PhotosUI
import SwiftUI
import UIKit

struct ProfileRootView: View {
    @StateObject private var presenter: ProfilePresenter
    @StateObject private var router: ProfileRouter
    @State private var isLogoutConfirmationPresented = false
    private let imageLoader: any AuthorizedImageLoading
    private let makeLikedStoresView: () -> AnyView
    private let makeMyPostsView: (String) -> AnyView
    private let makeLikedPostsView: () -> AnyView
    private let makeMyReviewsView: (String) -> AnyView
    private let makeChatListView: () -> AnyView
    private let makeUserSearchView: () -> AnyView
    private let makeDeveloperDiagnosticsView: () -> AnyView
    @State private var isChatListPresented = false
    @State private var isUserSearchPresented = false
    @State private var isDeveloperDiagnosticsPresented = false

    init(
        presenter: ProfilePresenter,
        router: ProfileRouter,
        imageLoader: any AuthorizedImageLoading,
        makeLikedStoresView: @escaping () -> AnyView,
        makeMyPostsView: @escaping (String) -> AnyView,
        makeLikedPostsView: @escaping () -> AnyView,
        makeMyReviewsView: @escaping (String) -> AnyView,
        makeChatListView: @escaping () -> AnyView,
        makeUserSearchView: @escaping () -> AnyView,
        makeDeveloperDiagnosticsView: @escaping () -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeLikedStoresView = makeLikedStoresView
        self.makeMyPostsView = makeMyPostsView
        self.makeLikedPostsView = makeLikedPostsView
        self.makeMyReviewsView = makeMyReviewsView
        self.makeChatListView = makeChatListView
        self.makeUserSearchView = makeUserSearchView
        self.makeDeveloperDiagnosticsView = makeDeveloperDiagnosticsView
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                if let noticeMessage = presenter.viewState.noticeMessage,
                   let noticeTone = presenter.viewState.noticeTone {
                    ToastView(
                        message: noticeMessage,
                        tone: noticeTone == .success ? .success : .warning
                    )
                }

                HStack(alignment: .center, spacing: PikkoSpacing.md) {
                    AuthorizedAsyncImage(
                        path: presenter.viewState.profileImagePath,
                        loader: imageLoader,
                        contentMode: .fill,
                        cornerRadius: 32,
                        showsProgress: false
                    )
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        Text(presenter.viewState.displayName)
                            .font(PikkoTypography.hero)
                            .foregroundStyle(PikkoColor.primaryText)

                        Text(presenter.viewState.email)
                            .font(PikkoTypography.body)
                            .foregroundStyle(PikkoColor.secondaryText)

                        if !presenter.viewState.phoneNumber.isEmpty {
                            Text(presenter.viewState.phoneNumber)
                                .font(PikkoTypography.caption)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }
                    }

                    Spacer(minLength: PikkoSpacing.sm)

                    Button {
                        Task {
                            await presenter.send(.editProfileTapped)
                        }
                    } label: {
                        Text(presenter.viewState.editProfileActionTitle)
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.accentStrong)
                            .padding(.horizontal, PikkoSpacing.md)
                            .frame(height: 36)
                            .background(PikkoColor.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                                    .stroke(PikkoColor.line, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PikkoSpacing.xl)
                .background(PikkoColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
                .pikkoShadow(PikkoShadow.card)

                VStack(spacing: PikkoSpacing.md) {
                    PrimaryButton(
                        title: presenter.viewState.likedStoresActionTitle,
                        systemImage: "heart.fill"
                    ) {
                        Task {
                            await presenter.send(.likedStoresTapped)
                        }
                    }

                    SecondaryButton(
                        title: "채팅",
                        systemImage: "bubble.left.and.bubble.right"
                    ) {
                        isChatListPresented = true
                    }

                    SecondaryButton(
                        title: "유저 검색",
                        systemImage: "person.text.rectangle"
                    ) {
                        isUserSearchPresented = true
                    }

                    SecondaryButton(
                        title: presenter.viewState.myPostsActionTitle,
                        systemImage: "square.text.square"
                    ) {
                        Task {
                            await presenter.send(.myPostsTapped)
                        }
                    }

                    SecondaryButton(
                        title: presenter.viewState.likedPostsActionTitle,
                        systemImage: "heart.text.square.fill"
                    ) {
                        Task {
                            await presenter.send(.likedPostsTapped)
                        }
                    }

                    SecondaryButton(
                        title: presenter.viewState.myReviewsActionTitle,
                        systemImage: "star.bubble"
                    ) {
                        Task {
                            await presenter.send(.myReviewsTapped)
                        }
                    }

                    SecondaryButton(
                        title: presenter.viewState.logoutActionTitle,
                        systemImage: "rectangle.portrait.and.arrow.right"
                    ) {
                        isLogoutConfirmationPresented = true
                    }

                    #if DEBUG
                    SecondaryButton(
                        title: "개발자 진단",
                        systemImage: "wrench.and.screwdriver"
                    ) {
                        isDeveloperDiagnosticsPresented = true
                    }
                    #endif
                }
            }
            .padding(PikkoSpacing.xl)
        }
        .background(PikkoColor.background.ignoresSafeArea())
        .navigationDestination(isPresented: likedStoresPresentedBinding) {
            makeLikedStoresView()
        }
        .navigationDestination(isPresented: myPostsPresentedBinding) {
            if let userID = router.presentedMyPostsUserID {
                makeMyPostsView(userID)
            }
        }
        .navigationDestination(isPresented: likedPostsPresentedBinding) {
            makeLikedPostsView()
        }
        .navigationDestination(isPresented: myReviewsPresentedBinding) {
            if let userID = router.presentedMyReviewsUserID {
                makeMyReviewsView(userID)
            }
        }
        .navigationDestination(isPresented: $isChatListPresented) {
            makeChatListView()
        }
        .navigationDestination(isPresented: $isUserSearchPresented) {
            makeUserSearchView()
        }
        #if DEBUG
        .navigationDestination(isPresented: $isDeveloperDiagnosticsPresented) {
            makeDeveloperDiagnosticsView()
        }
        #endif
        .sheet(
            isPresented: profileEditorPresentedBinding,
            onDismiss: {
                Task {
                    await presenter.send(.profileEditorDismissed)
                }
            }
        ) {
            ProfileEditorView(
                presenter: presenter,
                imageLoader: imageLoader
            )
        }
        .pikkoScreen(title: presenter.viewState.title)
        .alert("로그아웃", isPresented: $isLogoutConfirmationPresented) {
            Button("취소", role: .cancel) {}
            Button("로그아웃", role: .destructive) {
                Task {
                    await presenter.send(.logoutTapped)
                }
            }
        } message: {
            Text("정말로 로그아웃 하겠습니까?")
        }
        .task {
            await presenter.send(.onAppear)
        }
    }

    private var likedStoresPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.isLikedStoresPresented },
            set: { isPresented in
                if !isPresented {
                    router.clearPendingRoute()
                }
            }
        )
    }

    private var profileEditorPresentedBinding: Binding<Bool> {
        Binding(
            get: { presenter.viewState.isEditingProfile },
            set: { isPresented in
                if !isPresented {
                    Task {
                        await presenter.send(.profileEditorDismissed)
                    }
                }
            }
        )
    }

    private var myPostsPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.presentedMyPostsUserID != nil },
            set: { isPresented in
                if !isPresented {
                    router.clearPendingRoute()
                }
            }
        )
    }

    private var likedPostsPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.isLikedPostsPresented },
            set: { isPresented in
                if !isPresented {
                    router.clearPendingRoute()
                }
            }
        )
    }

    private var myReviewsPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.presentedMyReviewsUserID != nil },
            set: { isPresented in
                if !isPresented {
                    router.clearPendingRoute()
                }
            }
        )
    }
}

private struct ProfileEditorView: View {
    @ObservedObject var presenter: ProfilePresenter
    let imageLoader: any AuthorizedImageLoading

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                    VStack(alignment: .center, spacing: PikkoSpacing.md) {
                        AuthorizedAsyncImage(
                            path: presenter.viewState.editorProfileImagePath,
                            loader: imageLoader,
                            contentMode: .fill,
                            cornerRadius: 40,
                            showsProgress: false
                        )
                        .frame(width: 96, height: 96)

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images,
                            preferredItemEncoding: .automatic
                        ) {
                            Text("프로필 이미지 변경")
                                .font(PikkoTypography.captionStrong)
                                .foregroundStyle(PikkoColor.accentStrong)
                                .padding(.horizontal, PikkoSpacing.md)
                                .frame(height: 36)
                                .background(PikkoColor.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                                        .stroke(PikkoColor.line, lineWidth: 1)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
                        }
                        .disabled(presenter.viewState.isUploadingProfileImage || presenter.viewState.isSavingProfile)

                        if presenter.viewState.isUploadingProfileImage {
                            LoadingView(message: "프로필 이미지 업로드 중")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: PikkoSpacing.sm) {
                        TextField(
                            "",
                            text: Binding(
                                get: { presenter.viewState.editorNick },
                                set: { value in
                                    Task { await presenter.send(.editorNickChanged(value)) }
                                }
                            ),
                            prompt: Text("닉네임").foregroundStyle(PikkoColor.secondaryText)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .authInputStyle()

                        TextField(
                            "",
                            text: Binding(
                                get: { presenter.viewState.editorPhoneNumber },
                                set: { value in
                                    Task { await presenter.send(.editorPhoneNumberChanged(value)) }
                                }
                            ),
                            prompt: Text("전화번호 (선택)").foregroundStyle(PikkoColor.secondaryText)
                        )
                        .keyboardType(.phonePad)
                        .authInputStyle()
                    }

                    if let uploadErrorMessage = presenter.viewState.profileImageUploadErrorMessage {
                        ToastView(message: uploadErrorMessage, tone: .warning)
                    }

                    if let editorErrorMessage = presenter.viewState.editorErrorMessage {
                        ToastView(message: editorErrorMessage, tone: .warning)
                    }

                    if let editorInfoMessage = presenter.viewState.editorInfoMessage {
                        ToastView(message: editorInfoMessage, tone: .success)
                    }

                    PrimaryButton(
                        title: presenter.viewState.saveProfileActionTitle,
                        systemImage: "square.and.arrow.down.fill",
                        isLoading: presenter.viewState.isSavingProfile,
                        isEnabled: presenter.viewState.canSaveProfile
                    ) {
                        Task {
                            await presenter.send(.saveProfileTapped)
                        }
                    }
                }
                .padding(PikkoSpacing.xl)
            }
            .background(PikkoColor.background.ignoresSafeArea())
            .navigationTitle(presenter.viewState.editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: selectedPhotoItem?.itemIdentifier) {
            guard let selectedPhotoItem else { return }
            await handleImageSelection(item: selectedPhotoItem)
        }
    }

    private func handleImageSelection(item: PhotosPickerItem) async {
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: rawData),
              let jpegData = image.jpegData(compressionQuality: 0.88),
              !jpegData.isEmpty else {
            return
        }

        await presenter.send(
            .profileImageDataSelected(
                jpegData,
                fileName: "profile-\(Int(Date().timeIntervalSince1970)).jpg"
            )
        )
    }
}

enum StoreListMode: Equatable, Sendable {
    case search(query: String)
    case liked(category: String?)

    var title: String {
        switch self {
        case .search:
            return "검색 결과"
        case .liked:
            return "찜한 가게"
        }
    }

    var subtitle: String? {
        switch self {
        case .search(let query):
            return "'\(query)' 검색 결과"
        case .liked:
            return "찜한 매장을 모아봤어요."
        }
    }

    var emptyTitle: String {
        switch self {
        case .search:
            return "검색 결과가 없어요"
        case .liked:
            return "찜한 가게가 없어요"
        }
    }

    var emptyMessage: String {
        switch self {
        case .search:
            return "다른 검색어로 다시 찾아보세요."
        case .liked:
            return "가게 상세나 홈에서 하트를 눌러 찜 목록을 채울 수 있어요."
        }
    }
}

enum StoreListAction {
    case onAppear
    case retryTapped
    case storeTapped(String)
    case storeAppeared(String)
    case likeTapped(String)
}

struct StoreListViewState {
    var title: String
    var subtitle: String?
    var stores: [StoreCard.Model] = []
    var nextCursor: String?
    var isLoading = true
    var isPaging = false
    var errorMessage: String?
    var emptyStateTitle: String?
    var emptyStateMessage: String?

    var showsEmptyState: Bool {
        !isLoading && stores.isEmpty
    }
}

@MainActor
protocol StoreListRouting: AnyObject {
    func routeToStoreDetail(storeID: String)
    func clearPendingRoute()
}

@MainActor
final class StoreListRouter: ObservableObject, StoreListRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToStoreDetail(storeID: String) {
        pendingRoute = .storeDetail(storeID: storeID)
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}

@MainActor
protocol StoreListInteracting {
    func loadInitialStores() async throws -> CursorPage<StoreSummary>
    func loadMoreStores(nextCursor: String) async throws -> CursorPage<StoreSummary>
    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool
}

@MainActor
struct StoreListInteractor: StoreListInteracting {
    private let mode: StoreListMode
    private let storeRepository: StoreRepository
    private let pageSize: Int

    init(
        mode: StoreListMode,
        storeRepository: StoreRepository,
        pageSize: Int = 20
    ) {
        self.mode = mode
        self.storeRepository = storeRepository
        self.pageSize = pageSize
    }

    func loadInitialStores() async throws -> CursorPage<StoreSummary> {
        do {
            switch mode {
            case .search(let query):
                return CursorPage(
                    items: try await storeRepository.searchStores(name: query),
                    nextCursor: nil
                )
            case .liked(let category):
                return try await storeRepository.fetchLikedStores(
                    category: category,
                    nextCursor: nil,
                    limit: pageSize
                )
            }
        } catch let error as NetworkError {
            throw map(error: error)
        } catch let error as StoreListFeatureError {
            throw error
        } catch {
            throw StoreListFeatureError.unavailable(message: "가게 목록을 불러오지 못했어요.")
        }
    }

    func loadMoreStores(nextCursor: String) async throws -> CursorPage<StoreSummary> {
        guard case .liked(let category) = mode else {
            return CursorPage(items: [], nextCursor: nil)
        }

        do {
            return try await storeRepository.fetchLikedStores(
                category: category,
                nextCursor: nextCursor,
                limit: pageSize
            )
        } catch let error as NetworkError {
            throw map(error: error)
        } catch let error as StoreListFeatureError {
            throw error
        } catch {
            throw StoreListFeatureError.unavailable(message: "찜 목록을 더 불러오지 못했어요.")
        }
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool {
        do {
            return try await storeRepository.updateLikeStatus(storeID: storeID, isLiked: isLiked)
        } catch let error as NetworkError {
            throw map(error: error)
        } catch let error as StoreListFeatureError {
            throw error
        } catch {
            throw StoreListFeatureError.unavailable(message: "가게 찜 상태를 변경하지 못했어요.")
        }
    }

    private func map(error: NetworkError) -> StoreListFeatureError {
        switch error {
        case .configuration(let configurationError):
            return .configurationRequired(message: configurationError.userMessage)
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired:
            return .authenticationRequired
        case .invalidRequest, .abnormalRequest:
            return .unavailable(message: "요청 정보를 다시 확인해 주세요.")
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return .unavailable(message: message)
        case .forbidden:
            return .unavailable(message: "가게 정보를 확인할 권한이 없어요.")
        case .rateLimited:
            return .unavailable(message: "요청이 많아요. 잠시 후 다시 시도해 주세요.")
        case .transport:
            return .unavailable(message: "네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "가게 목록 응답을 해석하지 못했어요.")
        }
    }
}

enum StoreListFeatureError: Error, Equatable {
    case authenticationRequired
    case configurationRequired(message: String)
    case unavailable(message: String)
}

extension StoreListFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 이용할 수 있어요."
        case .configurationRequired(let message), .unavailable(let message):
            return message
        }
    }
}

@MainActor
final class StoreListPresenter: ObservableObject {
    @Published private(set) var viewState: StoreListViewState

    private let mode: StoreListMode
    private let interactor: StoreListInteracting
    private let router: StoreListRouting
    private let distanceFormatter = DistanceFormatter()

    private var hasLoaded = false
    private var isPaging = false

    init(
        mode: StoreListMode,
        interactor: StoreListInteracting,
        router: StoreListRouting
    ) {
        self.mode = mode
        self.interactor = interactor
        self.router = router
        self.viewState = StoreListViewState(
            title: mode.title,
            subtitle: mode.subtitle
        )
    }

    func send(_ action: StoreListAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await loadStores()
        case .retryTapped:
            await loadStores()
        case .storeTapped(let storeID):
            router.routeToStoreDetail(storeID: storeID)
        case .storeAppeared(let storeID):
            await loadMoreIfNeeded(triggeredBy: storeID)
        case .likeTapped(let storeID):
            await toggleLike(for: storeID)
        }
    }

    private func loadStores() async {
        viewState.isLoading = true
        viewState.errorMessage = nil
        viewState.emptyStateTitle = nil
        viewState.emptyStateMessage = nil

        do {
            let page = try await interactor.loadInitialStores()
            viewState.stores = page.items.map(makeStoreCardModel)
            viewState.nextCursor = page.nextCursor
            hasLoaded = true

            if viewState.stores.isEmpty {
                viewState.emptyStateTitle = mode.emptyTitle
                viewState.emptyStateMessage = mode.emptyMessage
            }
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
            viewState.emptyStateTitle = mode.emptyTitle
            viewState.emptyStateMessage = resolveErrorMessage(from: error)
        }

        viewState.isLoading = false
    }

    private func loadMoreIfNeeded(triggeredBy storeID: String) async {
        guard case .liked = mode,
              !isPaging,
              let nextCursor = viewState.nextCursor,
              storeID == viewState.stores.last?.id else {
            return
        }

        isPaging = true
        viewState.isPaging = true
        defer {
            isPaging = false
            viewState.isPaging = false
        }

        do {
            let nextPage = try await interactor.loadMoreStores(nextCursor: nextCursor)
            viewState.stores.append(contentsOf: nextPage.items.map(makeStoreCardModel))
            viewState.nextCursor = nextPage.nextCursor
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func toggleLike(for storeID: String) async {
        let previousStores = viewState.stores

        guard let currentStore = previousStores.first(where: { $0.id == storeID }) else { return }

        let optimisticLikeStatus = !currentStore.isLiked
        if case .liked = mode, !optimisticLikeStatus {
            viewState.stores.removeAll { $0.id == storeID }
            updateEmptyStateIfNeeded()
        } else {
            applyLikeStatus(optimisticLikeStatus, to: storeID)
        }

        do {
            let confirmedLikeStatus = try await interactor.updateLikeStatus(
                storeID: storeID,
                isLiked: optimisticLikeStatus
            )

            switch mode {
            case .liked:
                if confirmedLikeStatus {
                    applyLikeStatus(true, to: storeID)
                } else {
                    viewState.stores.removeAll { $0.id == storeID }
                    updateEmptyStateIfNeeded()
                }
            case .search:
                applyLikeStatus(confirmedLikeStatus, to: storeID)
            }
        } catch {
            viewState.stores = previousStores
            updateEmptyStateIfNeeded()
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func updateEmptyStateIfNeeded() {
        if viewState.stores.isEmpty {
            viewState.emptyStateTitle = mode.emptyTitle
            viewState.emptyStateMessage = mode.emptyMessage
        } else {
            viewState.emptyStateTitle = nil
            viewState.emptyStateMessage = nil
        }
    }

    private func applyLikeStatus(_ isLiked: Bool, to storeID: String) {
        viewState.stores = viewState.stores.map { model in
            guard model.id == storeID else { return model }

            let delta: Int
            switch (model.isLiked, isLiked) {
            case (true, false):
                delta = -1
            case (false, true):
                delta = 1
            default:
                delta = 0
            }

            let updatedCount = max(model.pickCount + delta, 0)

            return .init(
                id: model.id,
                title: model.title,
                heroImagePath: model.heroImagePath,
                thumbnailPaths: model.thumbnailPaths,
                pickCount: updatedCount,
                likeText: "\(updatedCount)개",
                ratingText: model.ratingText,
                reviewCountText: model.reviewCountText,
                distanceText: model.distanceText,
                openTimeText: model.openTimeText,
                orderCountText: model.orderCountText,
                tags: model.tags,
                isLiked: isLiked,
                isPickupAvailable: model.isPickupAvailable
            )
        }
    }

    private func makeStoreCardModel(_ store: StoreSummary) -> StoreCard.Model {
        let tags = Array(normalizedTags(from: store).prefix(2))

        return .init(
            id: store.id,
            title: store.name,
            heroImagePath: store.imagePaths.first,
            thumbnailPaths: Array(store.imagePaths.dropFirst().prefix(2)),
            pickCount: store.likeCount,
            likeText: "\(store.likeCount)개",
            ratingText: formattedRating(from: store.totalRating),
            reviewCountText: "(\(store.totalReviewCount))",
            distanceText: formattedDistance(from: store.distanceMeters),
            openTimeText: formattedCloseTime(from: store.closeTime),
            orderCountText: "\(store.totalOrderCount)회",
            tags: tags,
            isLiked: store.isLiked,
            isPickupAvailable: isPickupAvailable(for: store)
        )
    }

    private func normalizedTags(from store: StoreSummary) -> [String] {
        if !store.hashTags.isEmpty {
            return store.hashTags
        }

        if store.isPicchelin {
            return ["#픽슐랭"]
        }

        return []
    }

    private func formattedRating(from rating: Double?) -> String {
        guard let rating else { return "-" }
        return String(format: "%.1f", rating)
    }

    private func formattedDistance(from distance: Double?) -> String {
        guard let distance else { return "-" }
        return distanceFormatter.string(fromMeters: distance)
    }

    private func formattedCloseTime(from closeTime: String?) -> String {
        guard let closeTime, !closeTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "-"
        }

        return closeTime
    }

    private func isPickupAvailable(for store: StoreSummary) -> Bool {
        guard let closeTime = store.closeTime else {
            return false
        }

        return !closeTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}

struct StoreListView: View {
    @ObservedObject var presenter: StoreListPresenter
    let imageLoader: any AuthorizedImageLoading

    var body: some View {
        Group {
            if presenter.viewState.isLoading && presenter.viewState.stores.isEmpty {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    ProfileListSkeletonView(title: presenter.viewState.title)
                        .padding(PikkoSpacing.xl)
                }
            } else if presenter.viewState.showsEmptyState {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    EmptyStateView(
                        title: presenter.viewState.emptyStateTitle ?? "표시할 가게가 없어요",
                        message: presenter.viewState.emptyStateMessage ?? "잠시 후 다시 시도해 주세요.",
                        actionTitle: "다시 시도하기",
                        action: {
                            Task { await presenter.send(.retryTapped) }
                        }
                    )
                    .padding(PikkoSpacing.xl)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                        if let subtitle = presenter.viewState.subtitle {
                            Text(subtitle)
                                .font(PikkoTypography.body)
                                .foregroundStyle(PikkoColor.secondaryText)
                        }

                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                        }

                        LazyVStack(spacing: PikkoSpacing.md) {
                            ForEach(presenter.viewState.stores) { store in
                                StoreCard(
                                    model: store,
                                    loader: imageLoader,
                                    style: .list,
                                    onLikeTapped: {
                                        Task { await presenter.send(.likeTapped(store.id)) }
                                    }
                                )
                                .onTapGesture {
                                    Task { await presenter.send(.storeTapped(store.id)) }
                                }
                                .onAppear {
                                    Task { await presenter.send(.storeAppeared(store.id)) }
                                }
                            }

                            if presenter.viewState.isPaging {
                                LoadingView(message: "가게를 더 불러오는 중")
                                    .padding(.vertical, PikkoSpacing.sm)
                            }
                        }
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.vertical, PikkoSpacing.lg)
                }
                .background(PikkoColor.background.ignoresSafeArea())
            }
        }
        .pikkoScreen(title: presenter.viewState.title)
    }
}

private struct ProfileListSkeletonView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            Text("\(title) 불러오는 중")
                .font(PikkoTypography.cardTitle)
                .foregroundStyle(PikkoColor.primaryText)

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
                    HStack(spacing: PikkoSpacing.md) {
                        SkeletonView(cornerRadius: PikkoRadius.card)
                            .frame(width: 72, height: 72)

                        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                            SkeletonView(cornerRadius: 6)
                                .frame(width: 140, height: 16)
                            SkeletonView(cornerRadius: 6)
                                .frame(width: 96, height: 12)
                            SkeletonView(cornerRadius: 6)
                                .frame(width: 180, height: 12)
                        }
                    }

                    SkeletonView(cornerRadius: 6)
                        .frame(height: 12)
                }
                .padding(PikkoSpacing.lg)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
                .pikkoShadow(PikkoShadow.card)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UserSearchRootView: View {
    private let authRepository: AuthRepository
    private let imageLoader: any AuthorizedImageLoading
    private let makeChatView: (String) -> AnyView

    @State private var query = ""
    @State private var users: [SearchUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var emptyMessage: String?
    @State private var presentedOpponentID: String?

    init(
        authRepository: AuthRepository,
        imageLoader: any AuthorizedImageLoading,
        makeChatView: @escaping (String) -> AnyView
    ) {
        self.authRepository = authRepository
        self.imageLoader = imageLoader
        self.makeChatView = makeChatView
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
            SearchBar(
                text: $query,
                placeholder: "닉네임으로 유저 검색",
                onSubmit: {
                    Task { await search() }
                },
                style: .compact
            )

            if isLoading {
                LoadingView(message: "유저를 검색하고 있어요")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = errorMessage ?? emptyMessage, users.isEmpty {
                EmptyStateView(
                    title: errorMessage == nil ? "검색 결과가 없어요" : "유저 검색 실패",
                    message: message,
                    systemImage: errorMessage == nil ? "person.crop.circle.badge.questionmark" : "exclamationmark.triangle",
                    actionTitle: errorMessage == nil ? nil : "다시 시도",
                    action: errorMessage == nil ? nil : {
                        Task { await search() }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: PikkoSpacing.sm) {
                        ForEach(users) { user in
                            Button {
                                presentedOpponentID = user.id
                            } label: {
                                HStack(spacing: PikkoSpacing.md) {
                                    AuthorizedAsyncImage(
                                        path: user.profileImagePath,
                                        loader: imageLoader,
                                        cornerRadius: 24,
                                        showsProgress: false
                                    )
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(user.nick)
                                            .font(PikkoTypography.bodyStrong)
                                            .foregroundStyle(PikkoColor.primaryText)
                                            .lineLimit(1)
                                        Text("채팅 시작")
                                            .font(PikkoTypography.caption)
                                            .foregroundStyle(PikkoColor.secondaryText)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(PikkoColor.tertiaryText)
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
        .background(PikkoColor.background.ignoresSafeArea())
        .navigationTitle("유저 검색")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: chatPresentedBinding) {
            if let presentedOpponentID {
                makeChatView(presentedOpponentID)
            }
        }
    }

    private var chatPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedOpponentID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedOpponentID = nil
                }
            }
        )
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            users = []
            errorMessage = nil
            emptyMessage = "검색어를 입력해 주세요."
            return
        }

        isLoading = true
        errorMessage = nil
        emptyMessage = nil
        defer { isLoading = false }

        do {
            users = try await authRepository.searchUsers(nick: trimmed)
            emptyMessage = users.isEmpty ? "일치하는 닉네임이 없어요." : nil
        } catch let error as NetworkError {
            if error.isAuthenticationFailure {
                errorMessage = "로그인 후 유저를 검색할 수 있어요."
            } else if case .rateLimited = error {
                errorMessage = "요청이 많아요. 잠시 후 다시 시도해 주세요."
            } else {
                errorMessage = "유저 검색을 완료하지 못했어요."
            }
            users = []
        } catch {
            errorMessage = "유저 검색을 완료하지 못했어요."
            users = []
        }
    }
}

#if DEBUG
private struct DeveloperLogDTO: Decodable, Sendable, Identifiable {
    var id: String { "\(date ?? "")-\(routePath ?? "")-\(statusCode ?? "")" }
    let date: String?
    let name: String?
    let method: String?
    let routePath: String?
    let body: String?
    let contentType: String?
    let statusCode: String?

    private enum CodingKeys: String, CodingKey {
        case date, name, method, body, contentType
        case routePath = "route_path"
        case statusCode = "status_code"
    }
}

private struct DeveloperLogListResponseDTO: Decodable, Sendable {
    let count: Int?
    let logs: [DeveloperLogDTO]?
}

private struct PushNotificationDebugRequestDTO: Encodable, Sendable {
    let userID: String
    let title: String
    let subtitle: String?
    let body: String

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case title, subtitle, body
    }
}

private struct VideoDebugListResponseDTO: Decodable, Sendable {
    let data: [VideoDebugDTO]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

private struct VideoDebugDTO: Decodable, Sendable, Identifiable {
    var id: String { videoID }
    let videoID: String
    let title: String
    let description: String
    let thumbnailURL: String?
    let likeCount: Int
    let isLiked: Bool

    private enum CodingKeys: String, CodingKey {
        case videoID = "video_id"
        case title, description
        case thumbnailURL = "thumbnail_url"
        case likeCount = "like_count"
        case isLiked = "is_liked"
    }
}

private struct VideoStreamDebugResponseDTO: Decodable, Sendable {
    let videoID: String
    let streamURL: String

    private enum CodingKeys: String, CodingKey {
        case videoID = "video_id"
        case streamURL = "stream_url"
    }
}

private struct DebugLikeRequestDTO: Encodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}

private struct DebugLikeResponseDTO: Decodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}

private struct StoreDebugFileResponseDTO: Decodable, Sendable {
    let storeImageURLs: [String]

    private enum CodingKeys: String, CodingKey {
        case storeImageURLs = "store_image_urls"
    }
}

private struct MenuDebugFileResponseDTO: Decodable, Sendable {
    let menuImageURL: String

    private enum CodingKeys: String, CodingKey {
        case menuImageURL = "menu_image_url"
    }
}

private struct StoreDebugMutationRequestDTO: Encodable, Sendable {
    var name: String
    var category: String
    var description: String
    var address: String
    var longitude: Double
    var latitude: Double
    var open: String
    var close: String
    var parkingGuide: String
    var storeImageURLs: [String]
    var hashTags: [String]
    var isPicchelin: Bool

    private enum CodingKeys: String, CodingKey {
        case name, category, description, address, longitude, latitude, open, close, hashTags
        case parkingGuide = "parking_guide"
        case storeImageURLs = "store_image_urls"
        case isPicchelin = "is_picchelin"
    }
}

private struct MenuDebugMutationRequestDTO: Encodable, Sendable {
    var name: String
    var description: String
    var originInformation: String
    var price: Int
    var category: String
    var tags: [String]
    var menuImageURL: String?
    var isSoldOut: Bool

    private enum CodingKeys: String, CodingKey {
        case name, description, price, category, tags
        case originInformation = "origin_information"
        case menuImageURL = "menu_image_url"
        case isSoldOut = "is_sold_out"
    }
}

private struct MenuDebugResponseDTO: Decodable, Sendable {
    let menuID: String?
    let storeID: String?
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case menuID = "menu_id"
        case storeID = "store_id"
        case name
    }
}

private struct DeveloperDiagnosticsClient: Sendable {
    let apiClient: any APIClientProtocol
    let appConfiguration: AppConfiguration

    func fetchCommon() async throws {
        let endpoint = Endpoint<EmptyResponse>(
            path: "/common",
            method: .get,
            authorizationPolicy: .none
        )
        _ = try await apiClient.execute(endpoint)
    }

    func fetchLogs() async throws -> DeveloperLogListResponseDTO {
        try await apiClient.execute(
            Endpoint<DeveloperLogListResponseDTO>(
                path: "/v1/log",
                method: .get,
                authorizationPolicy: .none
            )
        )
    }

    func sendPush(userID: String, title: String, subtitle: String?, body: String) async throws {
        let request = PushNotificationDebugRequestDTO(userID: userID, title: title, subtitle: subtitle, body: body)
        _ = try await apiClient.execute(
            Endpoint<EmptyResponse>(
                path: "/v1/notifications/push",
                method: .post,
                body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(request)),
                authorizationPolicy: .accessToken
            )
        )
    }

    func fetchVideos(next: String?) async throws -> VideoDebugListResponseDTO {
        let query = [
            next.map { URLQueryItem(name: "next", value: $0) },
            URLQueryItem(name: "limit", value: "5")
        ].compactMap { $0 }
        return try await apiClient.execute(
            Endpoint<VideoDebugListResponseDTO>(
                path: "/v1/videos",
                method: .get,
                query: query,
                authorizationPolicy: .accessToken
            )
        )
    }

    func fetchVideoStream(videoID: String) async throws -> URL {
        let response = try await apiClient.execute(
            Endpoint<VideoStreamDebugResponseDTO>(
                path: "/v1/videos/\(videoID)/stream",
                method: .get,
                authorizationPolicy: .accessToken
            )
        )
        return resolveURL(response.streamURL)
    }

    func updateVideoLike(videoID: String, isLiked: Bool) async throws -> Bool {
        let response = try await apiClient.execute(
            Endpoint<DebugLikeResponseDTO>(
                path: "/v1/videos/\(videoID)/like",
                method: .post,
                body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(DebugLikeRequestDTO(likeStatus: isLiked))),
                authorizationPolicy: .accessToken
            )
        )
        return response.likeStatus
    }

    func uploadStoreImages(_ files: [StoreReviewUploadFile]) async throws -> [String] {
        var builder = MultipartFormDataBuilder()
        for file in files {
            builder.addFile(fieldName: "files", fileName: file.fileName, mimeType: file.mimeType, fileData: file.data)
        }
        let response = try await apiClient.execute(
            Endpoint<StoreDebugFileResponseDTO>(
                path: "/v1/stores/files",
                method: .post,
                body: builder.build(),
                timeout: .upload,
                authorizationPolicy: .accessToken
            )
        )
        return response.storeImageURLs
    }

    func uploadMenuImage(_ file: StoreReviewUploadFile) async throws -> String {
        var builder = MultipartFormDataBuilder()
        builder.addFile(fieldName: "menu_image", fileName: file.fileName, mimeType: file.mimeType, fileData: file.data)
        let response = try await apiClient.execute(
            Endpoint<MenuDebugFileResponseDTO>(
                path: "/v1/menus/image",
                method: .post,
                body: builder.build(),
                timeout: .upload,
                authorizationPolicy: .accessToken
            )
        )
        return response.menuImageURL
    }

    func createStore(_ request: StoreDebugMutationRequestDTO) async throws {
        _ = try await apiClient.execute(
            Endpoint<StoreDetailResponseDTO>(
                path: "/v1/stores",
                method: .post,
                body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(request)),
                authorizationPolicy: .accessToken
            )
        )
    }

    func updateStore(storeID: String, request: StoreDebugMutationRequestDTO) async throws {
        _ = try await apiClient.execute(
            Endpoint<StoreDetailResponseDTO>(
                path: "/v1/stores/\(storeID)",
                method: .put,
                body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(request)),
                authorizationPolicy: .accessToken
            )
        )
    }

    func createMenu(storeID: String, request: MenuDebugMutationRequestDTO) async throws {
        _ = try await apiClient.execute(
            Endpoint<MenuDebugResponseDTO>(
                path: "/v1/menus/stores/\(storeID)",
                method: .post,
                body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(request)),
                authorizationPolicy: .accessToken
            )
        )
    }

    func updateMenu(menuID: String, request: MenuDebugMutationRequestDTO) async throws {
        _ = try await apiClient.execute(
            Endpoint<MenuDebugResponseDTO>(
                path: "/v1/menus/\(menuID)",
                method: .put,
                body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(request)),
                authorizationPolicy: .accessToken
            )
        )
    }

    private func resolveURL(_ value: String) -> URL {
        if let absolute = URL(string: value),
           absolute.scheme != nil {
            return absolute
        }
        return URL(string: value, relativeTo: appConfiguration.baseURL)?.absoluteURL ?? appConfiguration.baseURL!
    }
}

struct DeveloperDiagnosticsRootView: View {
    private let client: DeveloperDiagnosticsClient
    private let imageLoader: any AuthorizedImageLoading

    @State private var status = "대기 중"
    @State private var logs: [DeveloperLogDTO] = []
    @State private var videos: [VideoDebugDTO] = []
    @State private var videoNextCursor: String?
    @State private var player: AVPlayer?
    @State private var pushUserID = ""
    @State private var pushTitle = "Pikko 테스트"
    @State private var pushSubtitle = "Developer Diagnostics"
    @State private var pushBody = "푸시 테스트입니다."
    @State private var storeID = ""
    @State private var storeImages: [String] = []
    @State private var menuID = ""
    @State private var menuImage: String?
    @State private var selectedStoreImages: [PhotosPickerItem] = []
    @State private var selectedMenuImage: PhotosPickerItem?

    fileprivate init(
        client: DeveloperDiagnosticsClient,
        imageLoader: any AuthorizedImageLoading
    ) {
        self.client = client
        self.imageLoader = imageLoader
    }

    var body: some View {
        List {
            Section("상태") {
                Text(status)
                    .font(PikkoTypography.caption)
                    .foregroundStyle(PikkoColor.secondaryText)
            }

            Section("Common / Log") {
                Button("GET /common") { Task { await run("공통 정책 조회") { try await client.fetchCommon() } } }
                Button("GET /v1/log") { Task { await fetchLogs() } }
                ForEach(logs.prefix(5)) { log in
                    Text("\(log.method ?? "-") \(log.routePath ?? "-") \(log.statusCode ?? "-")")
                        .font(PikkoTypography.caption)
                }
            }

            Section("Push") {
                TextField("user_id", text: $pushUserID)
                TextField("title", text: $pushTitle)
                TextField("subtitle", text: $pushSubtitle)
                TextField("body", text: $pushBody)
                Button("POST /v1/notifications/push") {
                    Task {
                        await run("푸시 전송") {
                            try await client.sendPush(
                                userID: pushUserID,
                                title: pushTitle,
                                subtitle: pushSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : pushSubtitle,
                                body: pushBody
                            )
                        }
                    }
                }
            }

            Section("Video") {
                Button("GET /v1/videos") { Task { await fetchVideos(next: nil) } }
                if videoNextCursor != nil {
                    Button("다음 비디오 페이지") { Task { await fetchVideos(next: videoNextCursor) } }
                }
                ForEach(videos) { video in
                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        Text(video.title)
                            .font(PikkoTypography.bodyStrong)
                        Text(video.description)
                            .font(PikkoTypography.caption)
                            .lineLimit(2)
                        HStack {
                            Button("재생") { Task { await play(videoID: video.videoID) } }
                            Button(video.isLiked ? "좋아요 취소" : "좋아요") {
                                Task { await like(video: video) }
                            }
                        }
                    }
                }
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                }
            }

            Section("Admin Store") {
                TextField("store_id 수정 시 입력", text: $storeID)
                PhotosPicker(selection: $selectedStoreImages, maxSelectionCount: 5, matching: .images) {
                    Text("가게 이미지 선택")
                }
                Button("POST /v1/stores/files") { Task { await uploadStoreImages() } }
                Text(storeImages.joined(separator: "\n"))
                    .font(PikkoTypography.caption)
                Button("POST /v1/stores") { Task { await mutateStore(isUpdate: false) } }
                Button("PUT /v1/stores/{store_id}") { Task { await mutateStore(isUpdate: true) } }
            }

            Section("Admin Menu") {
                TextField("store_id", text: $storeID)
                TextField("menu_id 수정 시 입력", text: $menuID)
                PhotosPicker(selection: $selectedMenuImage, matching: .images) {
                    Text("메뉴 이미지 선택")
                }
                Button("POST /v1/menus/image") { Task { await uploadMenuImage() } }
                Text(menuImage ?? "업로드된 메뉴 이미지 없음")
                    .font(PikkoTypography.caption)
                Button("POST /v1/menus/stores/{store_id}") { Task { await mutateMenu(isUpdate: false) } }
                Button("PUT /v1/menus/{menu_id}") { Task { await mutateMenu(isUpdate: true) } }
            }
        }
        .navigationTitle("개발자 진단")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run(_ label: String, action: () async throws -> Void) async {
        status = "\(label) 실행 중"
        do {
            try await action()
            status = "\(label) 성공"
        } catch {
            status = "\(label) 실패: \(error.localizedDescription)"
        }
    }

    private func fetchLogs() async {
        status = "로그 조회 중"
        do {
            let response = try await client.fetchLogs()
            logs = response.logs ?? []
            status = "로그 \(response.count ?? logs.count)개 조회"
        } catch {
            status = "로그 조회 실패: \(error.localizedDescription)"
        }
    }

    private func fetchVideos(next: String?) async {
        status = "비디오 조회 중"
        do {
            let response = try await client.fetchVideos(next: next)
            videos = next == nil ? response.data : videos + response.data
            videoNextCursor = response.nextCursor
            status = "비디오 \(videos.count)개 조회"
        } catch {
            status = "비디오 조회 실패: \(error.localizedDescription)"
        }
    }

    private func play(videoID: String) async {
        status = "스트림 URL 조회 중"
        do {
            let url = try await client.fetchVideoStream(videoID: videoID)
            player = AVPlayer(url: url)
            player?.play()
            status = "비디오 재생 요청 완료"
        } catch {
            status = "스트림 조회 실패: \(error.localizedDescription)"
        }
    }

    private func like(video: VideoDebugDTO) async {
        await run("비디오 좋아요") {
            let confirmed = try await client.updateVideoLike(videoID: video.videoID, isLiked: !video.isLiked)
            videos = videos.map { item in
                guard item.videoID == video.videoID else { return item }
                return VideoDebugDTO(
                    videoID: item.videoID,
                    title: item.title,
                    description: item.description,
                    thumbnailURL: item.thumbnailURL,
                    likeCount: max(item.likeCount + (confirmed ? 1 : -1), 0),
                    isLiked: confirmed
                )
            }
        }
    }

    private func uploadStoreImages() async {
        guard let files = await makeUploadFiles(from: selectedStoreImages), !files.isEmpty else {
            status = "가게 이미지를 선택해 주세요."
            return
        }
        await run("가게 이미지 업로드") {
            storeImages = try await client.uploadStoreImages(files)
            selectedStoreImages = []
        }
    }

    private func uploadMenuImage() async {
        guard let selectedMenuImage,
              let file = await makeUploadFiles(from: [selectedMenuImage])?.first else {
            status = "메뉴 이미지를 선택해 주세요."
            return
        }
        await run("메뉴 이미지 업로드") {
            menuImage = try await client.uploadMenuImage(file)
            self.selectedMenuImage = nil
        }
    }

    private func mutateStore(isUpdate: Bool) async {
        let request = StoreDebugMutationRequestDTO(
            name: "새싹 테스트 가게",
            category: "커피",
            description: "DEBUG 진단 화면에서 생성한 테스트 가게",
            address: "서울특별시 마포구 월드컵북로 400",
            longitude: 126.8997,
            latitude: 37.571,
            open: "09:00",
            close: "18:00",
            parkingGuide: "주차 불가",
            storeImageURLs: storeImages,
            hashTags: ["#테스트"],
            isPicchelin: false
        )
        await run(isUpdate ? "가게 수정" : "가게 등록") {
            if isUpdate {
                try await client.updateStore(storeID: storeID, request: request)
            } else {
                try await client.createStore(request)
            }
        }
    }

    private func mutateMenu(isUpdate: Bool) async {
        let request = MenuDebugMutationRequestDTO(
            name: "새싹 테스트 메뉴",
            description: "DEBUG 진단 화면에서 생성한 테스트 메뉴",
            originInformation: "원산지 테스트",
            price: 100,
            category: "대표 메뉴",
            tags: ["테스트"],
            menuImageURL: menuImage,
            isSoldOut: false
        )
        await run(isUpdate ? "메뉴 수정" : "메뉴 등록") {
            if isUpdate {
                try await client.updateMenu(menuID: menuID, request: request)
            } else {
                try await client.createMenu(storeID: storeID, request: request)
            }
        }
    }

    private func makeUploadFiles(from items: [PhotosPickerItem]) async -> [StoreReviewUploadFile]? {
        var files: [StoreReviewUploadFile] = []
        for (index, item) in items.enumerated() {
            guard let rawData = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let jpegData = image.jpegData(compressionQuality: 0.88),
                  !jpegData.isEmpty else {
                continue
            }
            files.append(
                StoreReviewUploadFile(
                    data: jpegData,
                    fileName: "debug-\(Int(Date().timeIntervalSince1970))-\(index).jpg",
                    mimeType: "image/jpeg"
                )
            )
        }
        return files
    }
}

@MainActor
struct DeveloperDiagnosticsBuilder {
    let apiClient: any APIClientProtocol
    let appConfiguration: AppConfiguration
    let imageLoader: any AuthorizedImageLoading

    func build() -> DeveloperDiagnosticsRootView {
        DeveloperDiagnosticsRootView(
            client: DeveloperDiagnosticsClient(apiClient: apiClient, appConfiguration: appConfiguration),
            imageLoader: imageLoader
        )
    }
}
#endif

@MainActor
struct UserSearchBuilder {
    let authRepository: AuthRepository
    let imageLoader: any AuthorizedImageLoading
    let makeChatView: (String) -> AnyView

    func build() -> UserSearchRootView {
        UserSearchRootView(
            authRepository: authRepository,
            imageLoader: imageLoader,
            makeChatView: makeChatView
        )
    }
}

struct StoreListRootView: View {
    @StateObject private var presenter: StoreListPresenter
    @StateObject private var router: StoreListRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeStoreDetailView: (String) -> AnyView

    @State private var presentedStoreID: String?

    init(
        presenter: StoreListPresenter,
        router: StoreListRouter,
        imageLoader: any AuthorizedImageLoading,
        makeStoreDetailView: @escaping (String) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeStoreDetailView = makeStoreDetailView
    }

    var body: some View {
        StoreListView(
            presenter: presenter,
            imageLoader: imageLoader
        )
        .task {
            await presenter.send(.onAppear)
        }
        .onChange(of: router.pendingRoute) { _, route in
            guard case let .some(.storeDetail(storeID)) = route else { return }
            presentedStoreID = storeID
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            }
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
}

@MainActor
struct StoreListBuilder {
    private let mode: StoreListMode
    private let storeRepository: StoreRepository
    private let imageLoader: any AuthorizedImageLoading
    private let makeStoreDetailView: (String) -> AnyView

    init(
        mode: StoreListMode,
        storeRepository: StoreRepository,
        imageLoader: any AuthorizedImageLoading,
        makeStoreDetailView: @escaping (String) -> AnyView
    ) {
        self.mode = mode
        self.storeRepository = storeRepository
        self.imageLoader = imageLoader
        self.makeStoreDetailView = makeStoreDetailView
    }

    func build() -> StoreListRootView {
        let router = StoreListRouter()
        let interactor = StoreListInteractor(
            mode: mode,
            storeRepository: storeRepository
        )
        let presenter = StoreListPresenter(
            mode: mode,
            interactor: interactor,
            router: router
        )
        return StoreListRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeStoreDetailView: makeStoreDetailView
        )
    }
}

enum CommunityPostListMode: Equatable, Sendable {
    case mine(userID: String, category: String?)
    case liked(category: String?)

    var title: String {
        switch self {
        case .mine:
            return "내 글"
        case .liked:
            return "좋아요한 글"
        }
    }

    var subtitle: String {
        switch self {
        case .mine:
            return "내가 작성한 커뮤니티 게시글을 모아봤어요."
        case .liked:
            return "좋아요한 게시글을 다시 확인할 수 있어요."
        }
    }

    var emptyTitle: String {
        switch self {
        case .mine:
            return "작성한 글이 없어요"
        case .liked:
            return "좋아요한 글이 없어요"
        }
    }

    var emptyMessage: String {
        switch self {
        case .mine:
            return "커뮤니티에서 첫 글을 작성해 보세요."
        case .liked:
            return "좋아요를 누른 게시글이 여기에 모여요."
        }
    }
}

enum CommunityPostListAction {
    case onAppear
    case refreshRequested
    case retryTapped
    case postTapped(String)
    case postAppeared(String)
    case likeTapped(String)
    case storeSnippetTapped(String)
}

struct CommunityPostListViewState {
    var title: String
    var subtitle: String
    var posts: [CommunityCard.Model] = []
    var nextCursor: String?
    var isLoading = true
    var isPaging = false
    var errorMessage: String?
    var emptyStateTitle: String?
    var emptyStateMessage: String?

    var showsEmptyState: Bool {
        !isLoading && posts.isEmpty
    }
}

@MainActor
protocol CommunityPostListRouting: AnyObject {
    func routeToPostDetail(postID: String)
    func routeToStoreDetail(storeID: String)
    func clearPendingRoute()
}

@MainActor
final class CommunityPostListRouter: ObservableObject, CommunityPostListRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPostDetail(postID: String) {
        pendingRoute = .communityDetail(postID: postID)
    }

    func routeToStoreDetail(storeID: String) {
        pendingRoute = .storeDetail(storeID: storeID)
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}

@MainActor
protocol CommunityPostListInteracting {
    func loadInitialPosts() async throws -> CursorPage<CommunityPostSummary>
    func loadMorePosts(nextCursor: String) async throws -> CursorPage<CommunityPostSummary>
    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool
}

@MainActor
struct CommunityPostListInteractor: CommunityPostListInteracting {
    private let mode: CommunityPostListMode
    private let communityRepository: CommunityRepository
    private let pageSize: Int

    init(
        mode: CommunityPostListMode,
        communityRepository: CommunityRepository,
        pageSize: Int = 5
    ) {
        self.mode = mode
        self.communityRepository = communityRepository
        self.pageSize = pageSize
    }

    func loadInitialPosts() async throws -> CursorPage<CommunityPostSummary> {
        do {
            switch mode {
            case .mine(let userID, let category):
                return try await communityRepository.fetchUserPosts(
                    userID: userID,
                    category: category,
                    nextCursor: nil,
                    limit: pageSize
                )
            case .liked(let category):
                return try await communityRepository.fetchLikedPosts(
                    category: category,
                    nextCursor: nil,
                    limit: pageSize
                )
            }
        } catch let error as NetworkError {
            throw map(error)
        } catch let error as CommunityPostListFeatureError {
            throw error
        } catch {
            throw CommunityPostListFeatureError.unavailable(message: "게시글 목록을 불러오지 못했어요.")
        }
    }

    func loadMorePosts(nextCursor: String) async throws -> CursorPage<CommunityPostSummary> {
        do {
            switch mode {
            case .mine(let userID, let category):
                return try await communityRepository.fetchUserPosts(
                    userID: userID,
                    category: category,
                    nextCursor: nextCursor,
                    limit: pageSize
                )
            case .liked(let category):
                return try await communityRepository.fetchLikedPosts(
                    category: category,
                    nextCursor: nextCursor,
                    limit: pageSize
                )
            }
        } catch let error as NetworkError {
            throw map(error)
        } catch let error as CommunityPostListFeatureError {
            throw error
        } catch {
            throw CommunityPostListFeatureError.unavailable(message: "게시글을 더 불러오지 못했어요.")
        }
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        do {
            return try await communityRepository.updateLikeStatus(postID: postID, isLiked: isLiked)
        } catch let error as NetworkError {
            throw map(error)
        } catch let error as CommunityPostListFeatureError {
            throw error
        } catch {
            throw CommunityPostListFeatureError.unavailable(message: "좋아요 상태를 변경하지 못했어요.")
        }
    }

    private func map(_ error: NetworkError) -> CommunityPostListFeatureError {
        switch error {
        case .configuration(let configurationError):
            return .configurationRequired(message: configurationError.userMessage)
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired:
            return .authenticationRequired
        case .invalidRequest, .abnormalRequest:
            return .unavailable(message: "요청 정보를 다시 확인해 주세요.")
        case .forbidden:
            return .unavailable(message: "게시글을 확인할 권한이 없어요.")
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "요청이 많아요. 잠시 후 다시 시도해 주세요.")
        case .transport:
            return .unavailable(message: "네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "게시글 목록 응답을 해석하지 못했어요.")
        }
    }
}

enum CommunityPostListFeatureError: Error, Equatable {
    case authenticationRequired
    case configurationRequired(message: String)
    case unavailable(message: String)
}

extension CommunityPostListFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 이용할 수 있어요."
        case .configurationRequired(let message), .unavailable(let message):
            return message
        }
    }
}

@MainActor
final class CommunityPostListPresenter: ObservableObject {
    @Published private(set) var viewState: CommunityPostListViewState

    private let mode: CommunityPostListMode
    private let interactor: CommunityPostListInteracting
    private let router: CommunityPostListRouting
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private var hasLoaded = false
    private var isPaging = false

    init(
        mode: CommunityPostListMode,
        interactor: CommunityPostListInteracting,
        router: CommunityPostListRouting
    ) {
        self.mode = mode
        self.interactor = interactor
        self.router = router
        self.viewState = CommunityPostListViewState(
            title: mode.title,
            subtitle: mode.subtitle
        )
        self.relativeDateFormatter.locale = Locale(identifier: "ko_KR")
        self.relativeDateFormatter.unitsStyle = .full
    }

    func send(_ action: CommunityPostListAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await loadPosts()
        case .refreshRequested, .retryTapped:
            await loadPosts()
        case .postTapped(let postID):
            router.routeToPostDetail(postID: postID)
        case .postAppeared(let postID):
            await loadMoreIfNeeded(triggeredBy: postID)
        case .likeTapped(let postID):
            await toggleLike(for: postID)
        case .storeSnippetTapped(let storeID):
            router.routeToStoreDetail(storeID: storeID)
        }
    }

    private func loadPosts() async {
        viewState.isLoading = true
        viewState.errorMessage = nil
        viewState.emptyStateTitle = nil
        viewState.emptyStateMessage = nil

        do {
            let page = try await interactor.loadInitialPosts()
            viewState.posts = page.items.map(makeCommunityCardModel)
            viewState.nextCursor = page.nextCursor
            hasLoaded = true
            updateEmptyStateIfNeeded()
        } catch {
            viewState.posts = []
            viewState.nextCursor = nil
            viewState.errorMessage = resolveErrorMessage(from: error)
            viewState.emptyStateTitle = mode.emptyTitle
            viewState.emptyStateMessage = resolveErrorMessage(from: error)
        }

        viewState.isLoading = false
    }

    private func loadMoreIfNeeded(triggeredBy postID: String) async {
        guard !isPaging,
              let nextCursor = viewState.nextCursor,
              postID == viewState.posts.last?.id else {
            return
        }

        isPaging = true
        viewState.isPaging = true
        defer {
            isPaging = false
            viewState.isPaging = false
        }

        do {
            let nextPage = try await interactor.loadMorePosts(nextCursor: nextCursor)
            viewState.posts.append(contentsOf: nextPage.items.map(makeCommunityCardModel))
            viewState.nextCursor = nextPage.nextCursor
            updateEmptyStateIfNeeded()
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func toggleLike(for postID: String) async {
        let previousPosts = viewState.posts

        guard let currentPost = previousPosts.first(where: { $0.id == postID }) else { return }

        let optimisticLikeStatus = !currentPost.isLiked
        if case .liked = mode, !optimisticLikeStatus {
            viewState.posts.removeAll { $0.id == postID }
            updateEmptyStateIfNeeded()
        } else {
            applyLikeStatus(optimisticLikeStatus, to: postID)
        }

        do {
            let confirmedLikeStatus = try await interactor.updateLikeStatus(
                postID: postID,
                isLiked: optimisticLikeStatus
            )

            switch mode {
            case .liked:
                if confirmedLikeStatus {
                    applyLikeStatus(true, to: postID)
                } else {
                    viewState.posts.removeAll { $0.id == postID }
                    updateEmptyStateIfNeeded()
                }
            case .mine:
                applyLikeStatus(confirmedLikeStatus, to: postID)
            }
        } catch {
            viewState.posts = previousPosts
            updateEmptyStateIfNeeded()
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func updateEmptyStateIfNeeded() {
        if viewState.posts.isEmpty {
            viewState.emptyStateTitle = mode.emptyTitle
            viewState.emptyStateMessage = mode.emptyMessage
        } else {
            viewState.emptyStateTitle = nil
            viewState.emptyStateMessage = nil
        }
    }

    private func applyLikeStatus(_ isLiked: Bool, to postID: String) {
        viewState.posts = viewState.posts.map { model in
            guard model.id == postID else { return model }

            let delta: Int
            switch (model.isLiked, isLiked) {
            case (true, false):
                delta = -1
            case (false, true):
                delta = 1
            default:
                delta = 0
            }

            let currentLikeCount = Int(model.likeText.replacingOccurrences(of: "개", with: "")) ?? 0
            let updatedCount = max(currentLikeCount + delta, 0)

            return .init(
                id: model.id,
                authorName: model.authorName,
                authorAvatarPath: model.authorAvatarPath,
                timeText: model.timeText,
                title: model.title,
                bodyText: model.bodyText,
                likeText: "\(updatedCount)개",
                distanceText: model.distanceText,
                media: model.media,
                storeSnippet: model.storeSnippet,
                isLiked: isLiked
            )
        }
    }

    private func makeCommunityCardModel(_ post: CommunityPostSummary) -> CommunityCard.Model {
        CommunityCard.Model(
            id: post.id,
            authorName: post.creator.nick,
            authorAvatarPath: post.creator.profileImagePath,
            timeText: makeRelativeTimeText(from: post.createdAt),
            title: post.title,
            bodyText: post.content,
            likeText: "\(post.likeCount)개",
            distanceText: formattedDistance(from: post),
            media: post.mediaPaths.enumerated().map { index, path in
                .init(id: "\(post.id)-media-\(index)", path: path)
            },
            storeSnippet: post.store.map {
                .init(
                    id: $0.id,
                    title: $0.name,
                    subtitle: formattedStoreSubtitle(from: $0),
                    imagePath: $0.imagePaths.first
                )
            },
            isLiked: post.isLiked
        )
    }

    private func formattedDistance(from post: CommunityPostSummary) -> String {
        let _ = post
        return "-"
    }

    private func formattedStoreSubtitle(from store: CommunityPostStoreSummary) -> String {
        let categoryText = store.category ?? "가게"

        if let closeTime = store.closeTime,
           !closeTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(categoryText) · 마감 \(closeTime)"
        }

        return categoryText
    }

    private func makeRelativeTimeText(from date: Date?) -> String {
        guard let date else {
            return "방금 전"
        }

        let relativeText = relativeDateFormatter.localizedString(for: date, relativeTo: Date())
        if relativeText.hasPrefix("in ") || relativeText.hasPrefix("후") {
            return "방금 전"
        }
        return relativeText
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}

struct CommunityPostListView: View {
    @ObservedObject var presenter: CommunityPostListPresenter
    let imageLoader: any AuthorizedImageLoading

    var body: some View {
        Group {
            if presenter.viewState.isLoading && presenter.viewState.posts.isEmpty {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    ProfileListSkeletonView(title: presenter.viewState.title)
                        .padding(PikkoSpacing.xl)
                }
            } else if presenter.viewState.showsEmptyState {
                ZStack {
                    PikkoColor.background.ignoresSafeArea()

                    EmptyStateView(
                        title: presenter.viewState.emptyStateTitle ?? "표시할 게시글이 없어요",
                        message: presenter.viewState.emptyStateMessage ?? "잠시 후 다시 시도해 주세요.",
                        actionTitle: "다시 시도하기",
                        action: {
                            Task { await presenter.send(.retryTapped) }
                        }
                    )
                    .padding(PikkoSpacing.xl)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                        Text(presenter.viewState.subtitle)
                            .font(PikkoTypography.body)
                            .foregroundStyle(PikkoColor.secondaryText)

                        if let errorMessage = presenter.viewState.errorMessage {
                            ToastView(message: errorMessage, tone: .warning)
                        }

                        LazyVStack(spacing: PikkoSpacing.md) {
                            ForEach(presenter.viewState.posts) { post in
                                CommunityCard(
                                    model: post,
                                    loader: imageLoader,
                                    onCardTapped: {
                                        Task { await presenter.send(.postTapped(post.id)) }
                                    },
                                    onLikeTapped: {
                                        Task { await presenter.send(.likeTapped(post.id)) }
                                    },
                                    onStoreSnippetTapped: { storeID in
                                        Task { await presenter.send(.storeSnippetTapped(storeID)) }
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
                                .pikkoShadow(PikkoShadow.card)
                                .onAppear {
                                    Task { await presenter.send(.postAppeared(post.id)) }
                                }
                            }

                            if presenter.viewState.isPaging {
                                LoadingView(message: "게시글을 더 불러오는 중")
                                    .padding(.vertical, PikkoSpacing.sm)
                            }
                        }
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.vertical, PikkoSpacing.lg)
                }
                .background(PikkoColor.background.ignoresSafeArea())
            }
        }
        .pikkoScreen(title: presenter.viewState.title)
    }
}

struct CommunityPostListRootView: View {
    @StateObject private var presenter: CommunityPostListPresenter
    @StateObject private var router: CommunityPostListRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeCommunityDetailView: (String) -> AnyView
    private let makeStoreDetailView: (String) -> AnyView

    @State private var presentedPostID: String?
    @State private var presentedStoreID: String?

    init(
        presenter: CommunityPostListPresenter,
        router: CommunityPostListRouter,
        imageLoader: any AuthorizedImageLoading,
        makeCommunityDetailView: @escaping (String) -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeCommunityDetailView = makeCommunityDetailView
        self.makeStoreDetailView = makeStoreDetailView
    }

    var body: some View {
        CommunityPostListView(
            presenter: presenter,
            imageLoader: imageLoader
        )
        .task {
            await presenter.send(.onAppear)
        }
        .onChange(of: router.pendingRoute) { _, route in
            switch route {
            case let .communityDetail(postID):
                presentedPostID = postID
            case let .storeDetail(storeID):
                presentedStoreID = storeID
            default:
                break
            }
        }
        .navigationDestination(isPresented: postDetailPresentedBinding) {
            if let presentedPostID {
                makeCommunityDetailView(presentedPostID)
            }
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            }
        }
    }

    private var postDetailPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedPostID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedPostID = nil
                    router.clearPendingRoute()
                    Task { await presenter.send(.refreshRequested) }
                }
            }
        )
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
}

@MainActor
struct CommunityPostListBuilder {
    private let mode: CommunityPostListMode
    private let communityRepository: CommunityRepository
    private let imageLoader: any AuthorizedImageLoading
    private let makeCommunityDetailView: (String) -> AnyView
    private let makeStoreDetailView: (String) -> AnyView

    init(
        mode: CommunityPostListMode,
        communityRepository: CommunityRepository,
        imageLoader: any AuthorizedImageLoading,
        makeCommunityDetailView: @escaping (String) -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView
    ) {
        self.mode = mode
        self.communityRepository = communityRepository
        self.imageLoader = imageLoader
        self.makeCommunityDetailView = makeCommunityDetailView
        self.makeStoreDetailView = makeStoreDetailView
    }

    func build() -> CommunityPostListRootView {
        let router = CommunityPostListRouter()
        let interactor = CommunityPostListInteractor(
            mode: mode,
            communityRepository: communityRepository
        )
        let presenter = CommunityPostListPresenter(
            mode: mode,
            interactor: interactor,
            router: router
        )

        return CommunityPostListRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeCommunityDetailView: makeCommunityDetailView,
            makeStoreDetailView: makeStoreDetailView
        )
    }
}

enum ReviewComposerAction: Equatable {
    case onAppear
    case ratingChanged(Int)
    case contentChanged(String)
    case imagesUploadRequested([StoreReviewUploadFile])
    case existingImageRemoved(String)
    case submitTapped
}

struct ReviewComposerViewState: Equatable {
    var title = "리뷰 작성"
    var storeName: String?
    var rating = 0
    var content = ""
    var existingImagePaths: [String] = []
    var uploadedImagePaths: [String] = []
    var isLoadingInitialReview = false
    var isUploadingImages = false
    var isSaving = false
    var errorMessage: String?
    var successMessage: String?
    var infoMessage: String?

    var imageCount: Int {
        existingImagePaths.count + uploadedImagePaths.count
    }

    var canSubmit: Bool {
        rating >= 1
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoadingInitialReview
            && !isUploadingImages
            && !isSaving
    }
}

enum ReviewComposerFeatureError: Error, Equatable {
    case invalidInput(String)
    case saveFailed(String)
    case authenticationRequired
    case notFound(String)
    case permissionDenied(String)
    case duplicate(String)

    var userMessage: String {
        switch self {
        case .invalidInput(let message),
             .saveFailed(let message),
             .notFound(let message),
             .permissionDenied(let message),
             .duplicate(let message):
            return message
        case .authenticationRequired:
            return "로그인 후 리뷰를 작성할 수 있어요."
        }
    }
}

@MainActor
protocol ReviewComposerInteracting {
    func loadInitialReviewIfNeeded(context: ReviewComposerContext) async throws -> UserStoreReview?
    func uploadImages(storeID: String, files: [StoreReviewUploadFile]) async throws -> [String]
    func submitReview(context: ReviewComposerContext, draft: StoreReviewDraft) async throws -> UserStoreReview
}

@MainActor
struct ReviewComposerInteractor: ReviewComposerInteracting {
    private let reviewRepository: ReviewRepository

    init(reviewRepository: ReviewRepository) {
        self.reviewRepository = reviewRepository
    }

    func loadInitialReviewIfNeeded(context: ReviewComposerContext) async throws -> UserStoreReview? {
        guard case .edit(let reviewID) = context.mode else { return nil }
        do {
            return try await reviewRepository.fetchReviewDetail(storeID: context.storeID, reviewID: reviewID)
        } catch {
            throw map(error: error, fallback: "리뷰 정보를 불러오지 못했어요.")
        }
    }

    func uploadImages(storeID: String, files: [StoreReviewUploadFile]) async throws -> [String] {
        do {
            return try await reviewRepository.uploadReviewImages(storeID: storeID, files: files)
        } catch {
            throw map(error: error, fallback: "리뷰 이미지를 업로드하지 못했어요.")
        }
    }

    func submitReview(context: ReviewComposerContext, draft: StoreReviewDraft) async throws -> UserStoreReview {
        do {
            switch context.mode {
            case .create:
                return try await reviewRepository.createReview(storeID: context.storeID, draft: draft)
            case .edit(let reviewID):
                return try await reviewRepository.updateReview(storeID: context.storeID, reviewID: reviewID, draft: draft)
            }
        } catch {
            throw map(error: error, fallback: "리뷰를 저장하지 못했어요.")
        }
    }

    private func map(error: Error, fallback: String) -> ReviewComposerFeatureError {
        guard let networkError = error as? NetworkError else {
            return .saveFailed(fallback)
        }
        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }
        switch networkError {
        case .notFound:
            return .notFound("삭제되었거나 찾을 수 없는 리뷰입니다.")
        case .conflict:
            return .duplicate("이미 이 주문에 대한 리뷰를 작성했어요.")
        case .businessAuthorization, .forbidden:
            return .permissionDenied("리뷰 작성 권한이 없습니다.")
        case .invalidRequest:
            return .invalidInput("리뷰 내용과 별점을 다시 확인해 주세요.")
        case .abnormalRequest(let message):
            return .invalidInput(message)
        case .transport:
            return .saveFailed("네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
        default:
            return .saveFailed(fallback)
        }
    }
}

@MainActor
final class ReviewComposerPresenter: ObservableObject {
    @Published private(set) var viewState = ReviewComposerViewState()

    private let context: ReviewComposerContext
    private let interactor: ReviewComposerInteracting
    private let onSubmitted: (UserStoreReview) -> Void
    private var hasLoaded = false

    init(
        context: ReviewComposerContext,
        interactor: ReviewComposerInteracting,
        onSubmitted: @escaping (UserStoreReview) -> Void
    ) {
        self.context = context
        self.interactor = interactor
        self.onSubmitted = onSubmitted
        viewState.storeName = context.storeName
        viewState.title = context.isEditing ? "리뷰 수정" : "리뷰 작성"
    }

    func send(_ action: ReviewComposerAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadInitialReviewIfNeeded()
        case .ratingChanged(let rating):
            viewState.rating = min(max(rating, 0), 5)
            viewState.errorMessage = nil
            viewState.infoMessage = nil
        case .contentChanged(let content):
            viewState.content = content
            viewState.errorMessage = nil
            viewState.infoMessage = nil
        case .imagesUploadRequested(let files):
            await upload(files)
        case .existingImageRemoved(let path):
            viewState.existingImagePaths.removeAll { $0 == path }
            viewState.uploadedImagePaths.removeAll { $0 == path }
            viewState.infoMessage = "선택한 이미지를 제외했어요."
        case .submitTapped:
            await submit()
        }
    }

    private func loadInitialReviewIfNeeded() async {
        guard context.isEditing else { return }
        viewState.isLoadingInitialReview = true
        defer { viewState.isLoadingInitialReview = false }

        do {
            guard let review = try await interactor.loadInitialReviewIfNeeded(context: context) else { return }
            viewState.rating = review.rating
            viewState.content = review.content
            viewState.existingImagePaths = review.imagePaths
            viewState.storeName = viewState.storeName ?? review.store.name
        } catch let error as ReviewComposerFeatureError {
            viewState.errorMessage = error.userMessage
        } catch {
            viewState.errorMessage = "리뷰 정보를 불러오지 못했어요."
        }
    }

    private func upload(_ files: [StoreReviewUploadFile]) async {
        guard !files.isEmpty else { return }
        viewState.isUploadingImages = true
        viewState.errorMessage = nil
        viewState.infoMessage = nil
        defer { viewState.isUploadingImages = false }

        do {
            let paths = try await interactor.uploadImages(storeID: context.storeID, files: files)
            viewState.uploadedImagePaths.append(contentsOf: paths)
            viewState.infoMessage = "리뷰 이미지 \(paths.count)개를 업로드했어요."
        } catch let error as ReviewComposerFeatureError {
            Logger.shared.warning("Review image upload failed: \(error.userMessage)")
            viewState.errorMessage = error.userMessage
        } catch {
            Logger.shared.warning("Review image upload failed: \(error.localizedDescription)")
            viewState.errorMessage = "리뷰 이미지를 업로드하지 못했어요."
        }
    }

    private func submit() async {
        let trimmedContent = viewState.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard viewState.rating >= 1 else {
            viewState.errorMessage = "별점을 1점 이상 선택해 주세요."
            return
        }
        guard !trimmedContent.isEmpty else {
            viewState.errorMessage = "리뷰 내용을 입력해 주세요."
            return
        }

        viewState.isSaving = true
        viewState.errorMessage = nil
        defer { viewState.isSaving = false }

        do {
            let review = try await interactor.submitReview(
                context: context,
                draft: StoreReviewDraft(
                    content: trimmedContent,
                    rating: viewState.rating,
                    imagePaths: viewState.existingImagePaths + viewState.uploadedImagePaths,
                    orderCode: context.orderCode
                )
            )
            viewState.successMessage = context.isEditing ? "리뷰를 수정했어요." : "리뷰를 작성했어요."
            onSubmitted(review)
        } catch let error as ReviewComposerFeatureError {
            viewState.errorMessage = error.userMessage
        } catch {
            viewState.errorMessage = "리뷰를 저장하지 못했어요."
        }
    }
}

struct ReviewComposerRootView: View {
    @StateObject private var presenter: ReviewComposerPresenter
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    init(presenter: ReviewComposerPresenter) {
        _presenter = StateObject(wrappedValue: presenter)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PikkoSpacing.lg) {
                if let storeName = presenter.viewState.storeName {
                    Text(storeName)
                        .font(PikkoTypography.cardTitle)
                        .foregroundStyle(PikkoColor.primaryText)
                }

                ratingPicker
                reviewEditor
                imageSection

                if presenter.viewState.isLoadingInitialReview {
                    LoadingView(message: "리뷰 정보를 불러오는 중")
                }

                if presenter.viewState.isUploadingImages {
                    LoadingView(message: "리뷰 이미지 업로드 중")
                }

                if let infoMessage = presenter.viewState.infoMessage {
                    ToastView(message: infoMessage, tone: .success)
                }

                if let errorMessage = presenter.viewState.errorMessage {
                    ToastView(message: errorMessage, tone: .warning)
                }

                PrimaryButton(
                    title: "저장하기",
                    systemImage: "square.and.arrow.down.fill",
                    isLoading: presenter.viewState.isSaving,
                    isEnabled: presenter.viewState.canSubmit
                ) {
                    Task { await presenter.send(.submitTapped) }
                }
            }
            .padding(PikkoSpacing.xl)
        }
        .background(PikkoColor.background.ignoresSafeArea())
        .navigationTitle(presenter.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await presenter.send(.onAppear)
        }
        .onChange(of: selectedPhotoItems) { _, items in
            Task { await handleImageSelection(items) }
        }
        .onChange(of: presenter.viewState.successMessage) { _, message in
            guard message != nil else { return }
            dismiss()
        }
    }

    private var ratingPicker: some View {
        HStack(spacing: PikkoSpacing.sm) {
            ForEach(1...5, id: \.self) { rating in
                Button {
                    Task { await presenter.send(.ratingChanged(rating)) }
                } label: {
                    Image(systemName: rating <= presenter.viewState.rating ? "star.fill" : "star")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(PikkoColor.accentStrong)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reviewEditor: some View {
        TextEditor(
            text: Binding(
                get: { presenter.viewState.content },
                set: { value in
                    Task { await presenter.send(.contentChanged(value)) }
                }
            )
        )
        .frame(minHeight: 160)
        .padding(PikkoSpacing.md)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: max(0, 5 - presenter.viewState.imageCount),
                matching: .images,
                preferredItemEncoding: .automatic
            ) {
                Label(
                    presenter.viewState.imageCount == 0
                        ? "사진 추가"
                        : "사진 추가 \(presenter.viewState.imageCount)/5",
                    systemImage: "photo.on.rectangle.angled"
                )
                    .font(PikkoTypography.captionStrong)
                    .foregroundStyle(PikkoColor.accentStrong)
                    .padding(.horizontal, PikkoSpacing.md)
                    .frame(height: 36)
                    .background(PikkoColor.surfaceElevated)
                    .clipShape(Capsule())
            }
            .disabled(
                presenter.viewState.isUploadingImages
                    || presenter.viewState.isSaving
                    || presenter.viewState.imageCount >= 5
            )

            let imagePaths = presenter.viewState.existingImagePaths + presenter.viewState.uploadedImagePaths
            if !imagePaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PikkoSpacing.sm) {
                        ForEach(imagePaths, id: \.self) { path in
                            ReviewImageToken(path: path) {
                                Task { await presenter.send(.existingImageRemoved(path)) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleImageSelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var files: [StoreReviewUploadFile] = []
        for (index, item) in items.enumerated() {
            guard let rawData = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let jpegData = image.jpegData(compressionQuality: 0.88),
                  !jpegData.isEmpty else {
                continue
            }

            files.append(
                StoreReviewUploadFile(
                    data: jpegData,
                    fileName: "review-\(Int(Date().timeIntervalSince1970))-\(index).jpg",
                    mimeType: "image/jpeg"
                )
            )
        }

        selectedPhotoItems = []
        await presenter.send(.imagesUploadRequested(files))
    }
}

private struct ReviewImageToken: View {
    let path: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: PikkoSpacing.xs) {
            Text((path as NSString).lastPathComponent)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(PikkoColor.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PikkoSpacing.sm)
        .frame(height: 32)
        .background(PikkoColor.surfaceElevated)
        .clipShape(Capsule())
    }
}

@MainActor
struct ReviewComposerBuilder {
    let context: ReviewComposerContext
    let reviewRepository: ReviewRepository

    func build(onSubmitted: @escaping (UserStoreReview) -> Void) -> ReviewComposerRootView {
        let interactor = ReviewComposerInteractor(reviewRepository: reviewRepository)
        let presenter = ReviewComposerPresenter(context: context, interactor: interactor, onSubmitted: onSubmitted)
        return ReviewComposerRootView(presenter: presenter)
    }
}

private extension ReviewComposerContext {
    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var orderCode: String? {
        if case .create(let orderCode) = mode { return orderCode }
        return nil
    }
}

enum UserReviewListAction: Equatable {
    case onAppear
    case refreshRequested
    case reviewAppeared(String)
    case storeTapped(String)
    case editTapped(String)
    case deleteConfirmed(String)
}

struct UserReviewListViewState: Equatable {
    var title = "내 리뷰"
    var reviews: [UserReviewListItemViewState] = []
    var isInitialLoading = false
    var isRefreshing = false
    var isLoadingMore = false
    var deletingReviewID: String?
    var canLoadMore = false
    var nextCursor: String?
    var errorMessage: String?
    var emptyMessage: String?
}

struct UserReviewListItemViewState: Equatable, Identifiable {
    let id: String
    let storeID: String
    let storeName: String
    let storeImagePath: String?
    let ratingText: String
    let content: String
    let menuText: String
    let createdAtText: String
}

@MainActor
protocol UserReviewListInteracting {
    func fetchReviews(nextCursor: String?) async throws -> CursorPage<UserStoreReview>
    func deleteReview(storeID: String, reviewID: String) async throws
}

@MainActor
struct UserReviewListInteractor: UserReviewListInteracting {
    let userID: String
    let category: String?
    let reviewRepository: ReviewRepository

    func fetchReviews(nextCursor: String?) async throws -> CursorPage<UserStoreReview> {
        try await reviewRepository.fetchUserReviews(userID: userID, category: category, nextCursor: nextCursor, limit: 20)
    }

    func deleteReview(storeID: String, reviewID: String) async throws {
        try await reviewRepository.deleteReview(storeID: storeID, reviewID: reviewID)
    }
}

@MainActor
protocol UserReviewListRouting: AnyObject {
    func routeToStoreDetail(storeID: String)
    func routeToReviewComposer(context: ReviewComposerContext)
    func clearPendingRoute()
}

@MainActor
final class UserReviewListRouter: ObservableObject, UserReviewListRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToStoreDetail(storeID: String) {
        pendingRoute = .storeDetail(storeID: storeID)
    }

    func routeToReviewComposer(context: ReviewComposerContext) {
        pendingRoute = .reviewComposer(context)
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}

@MainActor
final class UserReviewListPresenter: ObservableObject {
    @Published private(set) var viewState = UserReviewListViewState()

    private let interactor: UserReviewListInteracting
    private let router: UserReviewListRouting
    private let dateParser = DateParser()
    private var reviews: [UserStoreReview] = []
    private var hasLoaded = false
    private var isRequestInFlight = false

    init(interactor: UserReviewListInteracting, router: UserReviewListRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: UserReviewListAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            await load(mode: .initial)
        case .refreshRequested:
            await load(mode: .refresh)
        case .reviewAppeared(let reviewID):
            guard reviewID == viewState.reviews.last?.id,
                  viewState.canLoadMore,
                  !viewState.isLoadingMore else { return }
            await load(mode: .loadMore)
        case .storeTapped(let reviewID):
            guard let review = reviews.first(where: { $0.id == reviewID }) else { return }
            router.routeToStoreDetail(storeID: review.store.id)
        case .editTapped(let reviewID):
            guard let review = reviews.first(where: { $0.id == reviewID }) else { return }
            router.routeToReviewComposer(
                context: ReviewComposerContext(
                    storeID: review.store.id,
                    storeName: review.store.name,
                    mode: .edit(reviewID: review.id)
                )
            )
        case .deleteConfirmed(let reviewID):
            await delete(reviewID: reviewID)
        }
    }

    func refreshAfterMutation() async {
        await load(mode: .refresh)
    }

    private func load(mode: LoadingMode) async {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        setLoading(mode, true)
        if mode != .loadMore {
            viewState.errorMessage = nil
        }

        do {
            let page = try await interactor.fetchReviews(nextCursor: mode == .loadMore ? viewState.nextCursor : nil)
            merge(page, mode: mode)
        } catch {
            viewState.errorMessage = map(error)
            if reviews.isEmpty {
                viewState.emptyMessage = viewState.errorMessage
            }
        }

        setLoading(mode, false)
        isRequestInFlight = false
    }

    private func merge(_ page: CursorPage<UserStoreReview>, mode: LoadingMode) {
        switch mode {
        case .initial, .refresh:
            reviews = page.items
        case .loadMore:
            let existingIDs = Set(reviews.map(\.id))
            reviews.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
        }

        viewState.nextCursor = page.nextCursor
        viewState.canLoadMore = page.nextCursor != nil
        viewState.reviews = reviews.map(map)
        viewState.emptyMessage = reviews.isEmpty ? "아직 작성한 리뷰가 없어요." : nil
        viewState.errorMessage = nil
    }

    private func delete(reviewID: String) async {
        guard viewState.deletingReviewID == nil,
              let review = reviews.first(where: { $0.id == reviewID }) else { return }
        viewState.deletingReviewID = reviewID
        defer { viewState.deletingReviewID = nil }

        do {
            try await interactor.deleteReview(storeID: review.store.id, reviewID: review.id)
            reviews.removeAll { $0.id == reviewID }
            viewState.reviews = reviews.map(map)
            viewState.emptyMessage = reviews.isEmpty ? "아직 작성한 리뷰가 없어요." : nil
        } catch {
            viewState.errorMessage = map(error)
        }
    }

    private func map(_ review: UserStoreReview) -> UserReviewListItemViewState {
        UserReviewListItemViewState(
            id: review.id,
            storeID: review.store.id,
            storeName: review.store.name,
            storeImagePath: review.store.imagePaths.first,
            ratingText: "\(review.rating)",
            content: review.content,
            menuText: review.orderedMenuNames.isEmpty ? "주문 메뉴 정보 없음" : review.orderedMenuNames.joined(separator: ", "),
            createdAtText: review.createdAt.map { dateParser.string(from: $0, format: "M월 d일") } ?? ""
        )
    }

    private func map(_ error: Error) -> String {
        guard let networkError = error as? NetworkError else {
            return "리뷰 목록을 불러오지 못했어요."
        }
        if networkError.isAuthenticationFailure {
            return "로그인 후 내 리뷰를 확인할 수 있어요."
        }
        switch networkError {
        case .notFound:
            return "삭제되었거나 찾을 수 없는 리뷰입니다."
        case .businessAuthorization, .forbidden:
            return "작성자만 수정/삭제할 수 있습니다."
        case .transport:
            return "네트워크 상태를 확인한 뒤 다시 시도해 주세요."
        default:
            return "리뷰 목록을 불러오지 못했어요."
        }
    }

    private func setLoading(_ mode: LoadingMode, _ isLoading: Bool) {
        switch mode {
        case .initial:
            viewState.isInitialLoading = isLoading
        case .refresh:
            viewState.isRefreshing = isLoading
        case .loadMore:
            viewState.isLoadingMore = isLoading
        }
    }
}

private extension UserReviewListPresenter {
    enum LoadingMode {
        case initial
        case refresh
        case loadMore
    }
}

struct UserReviewListRootView: View {
    @StateObject private var presenter: UserReviewListPresenter
    @StateObject private var router: UserReviewListRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeStoreDetailView: (String) -> AnyView
    private let makeReviewComposerView: (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView

    @State private var presentedStoreID: String?
    @State private var presentedReviewContext: ReviewComposerContext?
    @State private var reviewToDelete: UserReviewListItemViewState?

    init(
        presenter: UserReviewListPresenter,
        router: UserReviewListRouter,
        imageLoader: any AuthorizedImageLoading,
        makeStoreDetailView: @escaping (String) -> AnyView,
        makeReviewComposerView: @escaping (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeStoreDetailView = makeStoreDetailView
        self.makeReviewComposerView = makeReviewComposerView
    }

    var body: some View {
        Group {
            if presenter.viewState.isInitialLoading && presenter.viewState.reviews.isEmpty {
                ProfileListSkeletonView(title: "내 리뷰")
                    .padding(PikkoSpacing.xl)
            } else if let emptyMessage = presenter.viewState.emptyMessage,
                      presenter.viewState.reviews.isEmpty {
                EmptyStateView(
                    title: "내 리뷰",
                    message: emptyMessage,
                    systemImage: "star.bubble",
                    actionTitle: "다시 시도",
                    action: { Task { await presenter.send(.refreshRequested) } }
                )
                .padding(PikkoSpacing.xl)
            } else {
                reviewList
            }
        }
        .background(PikkoColor.background.ignoresSafeArea())
        .navigationTitle(presenter.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let errorMessage = presenter.viewState.errorMessage,
               !presenter.viewState.reviews.isEmpty {
                ToastView(message: errorMessage, tone: .warning)
                    .padding(PikkoSpacing.md)
            }
        }
        .confirmationDialog("리뷰를 삭제할까요?", isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                guard let reviewToDelete else { return }
                Task { await presenter.send(.deleteConfirmed(reviewToDelete.id)) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제한 리뷰는 복구할 수 없어요.")
        }
        .onChange(of: router.pendingRoute) { _, route in
            switch route {
            case .some(.storeDetail(let storeID)):
                presentedStoreID = storeID
            case .some(.reviewComposer(let context)):
                presentedReviewContext = context
            default:
                break
            }
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            }
        }
        .navigationDestination(isPresented: reviewComposerPresentedBinding) {
            if let presentedReviewContext {
                makeReviewComposerView(presentedReviewContext) { _ in
                    Task { await presenter.refreshAfterMutation() }
                }
            }
        }
        .task {
            await presenter.send(.onAppear)
        }
    }

    private var reviewList: some View {
        List {
            ForEach(presenter.viewState.reviews) { review in
                UserReviewRow(
                    review: review,
                    imageLoader: imageLoader,
                    onStoreTap: { Task { await presenter.send(.storeTapped(review.id)) } },
                    onEditTap: { Task { await presenter.send(.editTapped(review.id)) } },
                    onDeleteTap: { reviewToDelete = review }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    Task { await presenter.send(.reviewAppeared(review.id)) }
                }
            }

            if presenter.viewState.isLoadingMore {
                LoadingView(message: "리뷰 더 불러오는 중")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await presenter.send(.refreshRequested)
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { reviewToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    reviewToDelete = nil
                }
            }
        )
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

    private var reviewComposerPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedReviewContext != nil },
            set: { isPresented in
                if !isPresented {
                    presentedReviewContext = nil
                    router.clearPendingRoute()
                }
            }
        )
    }
}

private struct UserReviewRow: View {
    let review: UserReviewListItemViewState
    let imageLoader: any AuthorizedImageLoading
    let onStoreTap: () -> Void
    let onEditTap: () -> Void
    let onDeleteTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.md) {
            Button(action: onStoreTap) {
                HStack(alignment: .top, spacing: PikkoSpacing.md) {
                    AuthorizedAsyncImage(path: review.storeImagePath, loader: imageLoader, cornerRadius: PikkoRadius.card)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                        Text(review.storeName)
                            .font(PikkoTypography.cardTitle)
                            .foregroundStyle(PikkoColor.primaryText)
                        Text("별점 \(review.ratingText)")
                            .font(PikkoTypography.captionStrong)
                            .foregroundStyle(PikkoColor.accentStrong)
                        Text(review.createdAtText)
                            .font(PikkoTypography.caption)
                            .foregroundStyle(PikkoColor.secondaryText)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Text(review.content)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.primaryText)
                .lineLimit(3)

            Text(review.menuText)
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
                .lineLimit(1)

            HStack(spacing: PikkoSpacing.sm) {
                SecondaryButton(title: "수정", systemImage: "square.and.pencil", action: onEditTap)
                Button(role: .destructive, action: onDeleteTap) {
                    Label("삭제", systemImage: "trash")
                        .font(PikkoTypography.captionStrong)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }
}

@MainActor
struct UserReviewListBuilder {
    let userID: String
    let category: String?
    let reviewRepository: ReviewRepository
    let imageLoader: any AuthorizedImageLoading
    let makeStoreDetailView: (String) -> AnyView
    let makeReviewComposerView: (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView

    func build() -> UserReviewListRootView {
        let router = UserReviewListRouter()
        let interactor = UserReviewListInteractor(userID: userID, category: category, reviewRepository: reviewRepository)
        let presenter = UserReviewListPresenter(interactor: interactor, router: router)
        return UserReviewListRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeStoreDetailView: makeStoreDetailView,
            makeReviewComposerView: makeReviewComposerView
        )
    }
}
