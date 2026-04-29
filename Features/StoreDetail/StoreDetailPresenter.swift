import Combine
import Foundation

@MainActor
final class StoreDetailPresenter: ObservableObject {
    @Published private(set) var viewState = StoreDetailViewState()

    private let interactor: StoreDetailInteracting
    private let router: StoreDetailRouting
    private let cartStore: CartStore
    private let distanceFormatter = DistanceFormatter()

    private var hasLoaded = false
    private var storeDetail: StoreDetail?
    private var reviewPage: CursorPage<StoreReview> = .init(items: [], nextCursor: nil)
    private var reviewRatings: [StoreReviewRatingBreakdown] = []
    private var distanceMeters: Double?
    private var featuredMenuIDs: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    init(
        interactor: StoreDetailInteracting,
        router: StoreDetailRouting,
        cartStore: CartStore
    ) {
        self.interactor = interactor
        self.router = router
        self.cartStore = cartStore
        bindCartStore()
        bindOrderStatusChanges()
    }

    func send(_ action: StoreDetailAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await loadInitialContent()
        case .retryTapped:
            await loadInitialContent()
        case .loginRequiredTapped:
            router.routeToAuth()
        case .likeTapped:
            await toggleLike()
        case .directionsTapped:
            guard storeDetail?.latitude != nil, storeDetail?.longitude != nil else {
                viewState.errorMessage = "거리 정보가 없습니다."
                return
            }

            router.routeToDirections(
                storeName: viewState.storeName,
                address: storeDetail?.address,
                latitude: storeDetail?.latitude,
                longitude: storeDetail?.longitude
            )
        case .chatTapped:
            guard let storeDetail else {
                viewState.errorMessage = "가게 정보를 불러온 뒤 채팅을 시작할 수 있어요."
                return
            }
            router.routeToChat(
                target: .store(
                    storeID: storeDetail.id,
                    storeName: storeDetail.name,
                    ownerID: storeDetail.owner?.id,
                    ownerName: storeDetail.owner?.nick,
                    ownerProfileImagePath: storeDetail.owner?.profileImagePath
                )
            )
        case .menuFilterTapped(let filterID):
            guard let filter = viewState.menuFilters.first(where: { $0.id == filterID }) else {
                return
            }
            viewState.selectedMenuFilter = filter
            applyMenuSections()
        case .menuIncrementTapped(let menuID):
            updateMenuQuantity(menuID: menuID, delta: 1)
        case .menuDecrementTapped(let menuID):
            updateMenuQuantity(menuID: menuID, delta: -1)
        case .reviewWriteTapped:
            await routeToReviewComposerForCompletedOrder()
        case .reviewEditTapped:
            guard let reviewID = viewState.reviewPreview.id else { return }
            router.routeToReviewComposer(
                context: ReviewComposerContext(
                    storeID: viewState.storeID,
                    storeName: viewState.storeName,
                    mode: .edit(reviewID: reviewID)
                )
            )
        case .reviewDeleteTapped:
            await deleteFeaturedReview()
        case .reviewAuthorChatTapped(let authorID):
            routeToReviewAuthorChat(authorID: authorID)
        case .stickyCTATapped:
            guard viewState.stickyCartSummary.isEnabled else { return }
            router.routeToCart(storeID: viewState.storeID)
        }
    }

    private func bindCartStore() {
        cartStore.$summary
            .combineLatest(cartStore.$currentStoreID)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.syncCartState()
            }
            .store(in: &cancellables)
    }

    private func bindOrderStatusChanges() {
        NotificationCenter.default.publisher(for: .pikkoOrderStatusDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[OrderStatusChangeNotificationUserInfoKey.event] as? OrderStatusChangeNotification,
                      event.status == .completed else {
                    return
                }

                Task { @MainActor [weak self] in
                    await self?.refreshReviewEligibilityAfterOrderStatusChange()
                }
            }
            .store(in: &cancellables)
    }

    private func loadInitialContent() async {
        viewState.isLoading = true
        viewState.errorMessage = nil
        viewState.successMessage = nil
        viewState.emptyState = nil

        do {
            let content = try await interactor.loadInitialContent()
            apply(content: content)
            hasLoaded = true
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
            viewState.hasLoadedContent = false
            viewState.emptyState = makeFailureEmptyState(for: error)
        }

        viewState.isLoading = false
    }

    private func apply(content: StoreDetailContent) {
        storeDetail = content.detail
        reviewPage = content.reviewPage
        reviewRatings = content.reviewRatings
        distanceMeters = content.distanceMeters
        viewState.errorMessage = content.warningMessage
        viewState.successMessage = nil
        viewState.reviewEligibilityMessage = nil
        viewState.emptyState = nil
        viewState.hasLoadedContent = true

        featuredMenuIDs = Set(makeFeaturedMenuIDs(from: content.detail.menus))

        viewState.storeID = content.detail.id
        viewState.storeName = content.detail.name
        viewState.heroImages = content.detail.imagePaths
        viewState.isPicchelin = content.detail.isPicchelin
        viewState.isLiked = content.detail.isLiked
        viewState.ratingSummary = makeRatingSummary(from: content.detail)
        viewState.storeInfo = makeStoreInfo(from: content.detail, distanceMeters: content.distanceMeters)

        let filters = makeMenuFilters(from: content.detail.menus)
        viewState.menuFilters = filters
        if !filters.contains(viewState.selectedMenuFilter) {
            viewState.selectedMenuFilter = filters.first ?? .defaultOption
        }

        viewState.reviewRatings = makeReviewRatings(from: content.reviewRatings)
        viewState.reviewPreview = makeReviewPreview(
            from: content.reviewPage.items.first,
            totalReviewCount: content.detail.totalReviewCount
        )
        viewState.reviewableOrderCode = content.reviewEligibility.orderCode
        viewState.isReviewWritable = content.reviewEligibility.isWritable
        viewState.reviewDisabledReasonText = content.reviewEligibility.disabledReasonText

        syncCartState()
    }

    private func syncCartState() {
        guard let storeDetail else {
            viewState.menus = []
            viewState.menuSections = []
            viewState.stickyCartSummary = .placeholder
            return
        }

        viewState.menus = storeDetail.menus.map(makeMenuItem)
        applyMenuSections()

        let usesCurrentStoreCart = cartStore.currentStoreID == storeDetail.id
        let summary = usesCurrentStoreCart ? cartStore.summary : .empty
        let itemCount = usesCurrentStoreCart ? summary.itemCount : 0

        viewState.stickyCartSummary = StoreDetailStickyCartSummary(
            totalPriceText: itemCount > 0 ? summary.subtotalText : "0원",
            itemCountText: "\(itemCount)",
            buttonTitle: itemCount > 0 ? "결제하기" : "메뉴를 담아주세요",
            isEnabled: itemCount > 0
        )
    }

    private func toggleLike() async {
        guard var storeDetail else { return }

        let previousDetail = storeDetail
        let optimisticStatus = !storeDetail.isLiked
        storeDetail.isLiked = optimisticStatus
        storeDetail.likeCount = max(storeDetail.likeCount + (optimisticStatus ? 1 : -1), 0)
        self.storeDetail = storeDetail
        applyDetailSummary(storeDetail)

        do {
            let confirmedStatus = try await interactor.updateLikeStatus(isLiked: optimisticStatus)
            guard var latestDetail = self.storeDetail else { return }
            if latestDetail.isLiked != confirmedStatus {
                latestDetail.likeCount = max(latestDetail.likeCount + (confirmedStatus ? 1 : -1), 0)
            }
            latestDetail.isLiked = confirmedStatus
            self.storeDetail = latestDetail
            applyDetailSummary(latestDetail)
        } catch {
            self.storeDetail = previousDetail
            applyDetailSummary(previousDetail)
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func deleteFeaturedReview() async {
        guard let reviewID = viewState.reviewPreview.id else { return }
        viewState.errorMessage = nil
        viewState.successMessage = nil

        do {
            try await interactor.deleteReview(reviewID: reviewID)
            let remainingReviews = reviewPage.items.filter { $0.id != reviewID }
            reviewPage = CursorPage(items: remainingReviews, nextCursor: reviewPage.nextCursor)
            viewState.reviewPreview = makeReviewPreview(
                from: reviewPage.items.first,
                totalReviewCount: max((storeDetail?.totalReviewCount ?? 1) - 1, 0)
            )
            viewState.successMessage = "리뷰를 삭제했어요."
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func routeToReviewComposerForCompletedOrder() async {
        viewState.errorMessage = nil
        viewState.successMessage = nil
        viewState.reviewEligibilityMessage = nil

        do {
            let orderCode: String?
            if let cachedOrderCode = viewState.reviewableOrderCode {
                orderCode = cachedOrderCode
            } else {
                orderCode = try await interactor.findReviewableOrderCode()
            }
            guard let orderCode else {
                viewState.reviewEligibilityMessage = viewState.reviewDisabledReasonText
                    ?? "픽업 완료된 주문 내역에서 리뷰를 작성할 수 있어요."
                viewState.reviewEligibilityScrollTrigger += 1
                return
            }
            viewState.reviewableOrderCode = orderCode
            viewState.isReviewWritable = true
            viewState.reviewDisabledReasonText = nil

            router.routeToReviewComposer(
                context: ReviewComposerContext(
                    storeID: viewState.storeID,
                    storeName: viewState.storeName,
                    mode: .create(orderCode: orderCode)
                )
            )
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func refreshReviewEligibilityAfterOrderStatusChange() async {
        guard hasLoaded else { return }
        do {
            guard let orderCode = try await interactor.findReviewableOrderCode() else {
                return
            }
            viewState.reviewableOrderCode = orderCode
            viewState.isReviewWritable = true
            viewState.reviewDisabledReasonText = nil
            Logger.shared.debug(
                "[ReviewEligibility] storeId=\(viewState.storeID) orderCode=\(orderCode) source=statusNotification isWritable=true"
            )
        } catch {
            Logger.shared.warning("StoreDetail review eligibility refresh failed: \(error.localizedDescription)")
        }
    }

    private func routeToReviewAuthorChat(authorID: String) {
        guard let review = reviewPage.items.first(where: { $0.author.id == authorID }) else {
            viewState.errorMessage = "채팅 상대를 찾지 못했어요."
            return
        }

        router.routeToChat(
            target: .user(
                userID: review.author.id,
                nickname: review.author.nick,
                profileImagePath: review.author.profileImagePath
            )
        )
    }

    private func updateMenuQuantity(menuID: String, delta: Int) {
        guard let storeDetail,
              let menu = storeDetail.menus.first(where: { $0.id == menuID }),
              !menu.isSoldOut else {
            return
        }

        let currentQuantity = cartStore.quantity(for: menuID, in: storeDetail.id)
        let nextQuantity = max(currentQuantity + delta, 0)

        if case .replaceRequired = cartStore.decisionForUsingCart(with: storeDetail.id) {
            cartStore.replaceCart(for: storeDetail.id, storeName: storeDetail.name)
            viewState.errorMessage = "장바구니는 한 가게만 담을 수 있어요. 기존 장바구니를 현재 가게 기준으로 교체했어요."
        }

        cartStore.setQuantity(
            nextQuantity,
            menuID: menu.id,
            menuName: menu.name,
            unitPrice: menu.price,
            imagePath: menu.imagePath,
            storeID: storeDetail.id,
            storeName: storeDetail.name
        )

        // Reflect the updated cart state immediately instead of waiting for the
        // next Combine delivery cycle from CartStore.
        syncCartState()
    }

    private func applyDetailSummary(_ detail: StoreDetail) {
        viewState.isLiked = detail.isLiked
        viewState.ratingSummary = makeRatingSummary(from: detail)
    }

    private func applyMenuSections() {
        let selectedFilter = viewState.selectedMenuFilter
        let selectedMenus = viewState.menus.filter { menu in
            menu.filterIDs.contains(selectedFilter.id)
        }

        var sections: [StoreDetailMenuSection] = []

        if !selectedMenus.isEmpty {
            sections.append(
                StoreDetailMenuSection(
                    id: "selected-\(selectedFilter.id)",
                    title: sectionTitle(for: selectedFilter),
                    subtitle: sectionSubtitle(for: selectedFilter),
                    items: selectedMenus
                )
            )
        }

        if selectedFilter.id != "popular" {
            let featuredMenus = viewState.menus.filter { featuredMenuIDs.contains($0.id) }
            if !featuredMenus.isEmpty {
                sections.append(
                    StoreDetailMenuSection(
                        id: "popular",
                        title: "인기메뉴",
                        subtitle: "사용자들이 자주 담는 메뉴부터 확인해보세요",
                        items: featuredMenus
                    )
                )
            }
        }

        if sections.isEmpty, !viewState.menus.isEmpty {
            sections = [
                StoreDetailMenuSection(
                    id: "fallback",
                    title: "전체메뉴",
                    subtitle: nil,
                    items: viewState.menus
                )
            ]
        }

        viewState.menuSections = sections
    }

    private func makeMenuFilters(from menus: [StoreMenu]) -> [StoreDetailMenuFilter] {
        var filters: [StoreDetailMenuFilter] = [StoreDetailMenuFilter.defaultOption]

        if menus.contains(where: { featuredMenuIDs.contains($0.id) }) {
            filters.append(.init(id: "popular", title: "인기메뉴", systemImage: nil))
        }

        var seenCategoryIDs = Set<String>()
        for menu in menus {
            guard let category = normalizedCategoryTitle(menu.category) else { continue }
            let filterID = "category:\(slug(from: category))"
            guard seenCategoryIDs.insert(filterID).inserted else { continue }
            filters.append(.init(id: filterID, title: category, systemImage: nil))
        }

        if menus.contains(where: { $0.tags.contains(where: { $0.contains("시그니처") }) }) {
            filters.append(.init(id: "signature", title: "시그니처", systemImage: nil))
        }

        return filters
    }

    private func makeMenuItem(from menu: StoreMenu) -> StoreDetailMenuItem {
        var filterIDs = ["all"]

        if featuredMenuIDs.contains(menu.id) {
            filterIDs.append("popular")
        }

        if let category = normalizedCategoryTitle(menu.category) {
            filterIDs.append("category:\(slug(from: category))")
        }

        if menu.tags.contains(where: { $0.contains("시그니처") }) {
            filterIDs.append("signature")
        }

        return StoreDetailMenuItem(
            id: menu.id,
            badgeText: menu.tags.first,
            name: menu.name,
            description: menu.description ?? menu.originInformation ?? "메뉴 설명 준비 중",
            priceText: formatWon(menu.price),
            imagePath: menu.imagePath,
            isSoldOut: menu.isSoldOut,
            quantity: cartStore.quantity(for: menu.id, in: viewState.storeID),
            filterIDs: filterIDs
        )
    }

    private func makeRatingSummary(from detail: StoreDetail) -> StoreDetailRatingSummary {
        StoreDetailRatingSummary(
            likeCountText: "\(detail.likeCount)개",
            ratingText: ratingText(from: detail.totalRating),
            reviewCountText: "(\(detail.totalReviewCount))",
            orderCountText: "누적 주문 \(detail.totalOrderCount)회"
        )
    }

    private func makeStoreInfo(from detail: StoreDetail, distanceMeters: Double?) -> StoreDetailStoreInfo {
        let operatingHours: String
        switch (detail.openTime, detail.closeTime) {
        case let (.some(open), .some(close)):
            operatingHours = "\(open) ~ \(close)"
        case let (.some(open), .none):
            operatingHours = open
        case let (.none, .some(close)):
            operatingHours = close
        case (.none, .none):
            operatingHours = "운영시간 정보 없음"
        }

        let expectedPickupText: String
        if let minutes = detail.estimatedPickupMinutes {
            expectedPickupText = "예상 소요시간 \(minutes)분"
        } else {
            expectedPickupText = "예상 소요시간 정보 없음"
        }

        let distanceText: String
        if let distanceMeters {
            distanceText = distanceFormatter.string(fromMeters: distanceMeters)
        } else {
            distanceText = "거리 정보 없음"
        }

        return StoreDetailStoreInfo(
            address: detail.address ?? "주소 정보 없음",
            operatingHours: operatingHours,
            parkingInfo: detail.parkingGuide ?? "주차 정보 없음",
            expectedPickupText: expectedPickupText,
            distanceText: distanceText,
            descriptionText: detail.description ?? ""
        )
    }

    private func makeReviewPreview(from review: StoreReview?, totalReviewCount: Int) -> StoreDetailReviewPreview {
        guard let review else {
            return StoreDetailReviewPreview(
                id: nil,
                authorID: nil,
                title: "아직 등록된 리뷰가 없어요",
                body: "첫 번째 리뷰를 남기면 이 영역에 대표 후기가 표시됩니다.",
                keywordBadges: [],
                authorName: "리뷰 준비 중",
                authorAvatarPath: nil,
                metricSummary: "리뷰 \(totalReviewCount)개",
                ratingText: "-",
                showsActions: false,
                canChatWithAuthor: false
            )
        }

        let metricSummary = "리뷰 \(totalReviewCount)개 · 작성자 리뷰 \(review.userTotalReviewCount)개"
        let badges = Array(review.orderedMenuNames.prefix(3)).map { "#\($0)" }

        return StoreDetailReviewPreview(
            id: review.id,
            authorID: review.author.id,
            title: review.orderedMenuNames.first ?? "대표 리뷰",
            body: review.content,
            keywordBadges: badges,
            authorName: review.author.nick,
            authorAvatarPath: review.author.profileImagePath,
            metricSummary: metricSummary,
            ratingText: "\(review.rating)",
            showsActions: true,
            canChatWithAuthor: true
        )
    }

    private func makeReviewRatings(from ratings: [StoreReviewRatingBreakdown]) -> [StoreDetailReviewRatingBar] {
        let total = max(ratings.reduce(0) { $0 + $1.count }, 1)
        return ratings
            .sorted { $0.rating > $1.rating }
            .map { rating in
                StoreDetailReviewRatingBar(
                    rating: rating.rating,
                    count: rating.count,
                    ratio: Double(rating.count) / Double(total)
                )
            }
    }

    private func makeFeaturedMenuIDs(from menus: [StoreMenu]) -> [String] {
        let tagged = menus.filter { menu in
            menu.tags.contains(where: { $0.contains("인기") })
        }
        if !tagged.isEmpty {
            return tagged.map(\.id)
        }

        return Array(menus.prefix(3)).map(\.id)
    }

    private func normalizedCategoryTitle(_ category: String?) -> String? {
        guard let category = category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !category.isEmpty else {
            return nil
        }
        return category
    }

    private func slug(from value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func sectionTitle(for filter: StoreDetailMenuFilter) -> String {
        switch filter.id {
        case "all":
            return "전체메뉴"
        case "popular":
            return "인기메뉴"
        default:
            return filter.title
        }
    }

    private func sectionSubtitle(for filter: StoreDetailMenuFilter) -> String? {
        switch filter.id {
        case "all":
            return "가게에서 제공하는 전체 메뉴를 확인할 수 있어요"
        case "popular":
            return "사용자들이 자주 픽업한 메뉴"
        default:
            return nil
        }
    }

    private func ratingText(from value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f", value)
    }

    private func formatWon(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ko_KR")
        return "\(formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")원"
    }

    private func makeFailureEmptyState(for error: Error) -> StoreDetailEmptyState {
        if let featureError = error as? StoreDetailFeatureError {
            switch featureError {
            case .authenticationRequired:
                return StoreDetailEmptyState(
                    title: "로그인이 필요해요",
                    message: "가게 상세는 로그인 후 확인할 수 있어요. 인증 후 다시 시도해 주세요.",
                    actionTitle: "로그인하러 가기",
                    requiresAuthentication: true
                )
            case .unavailable(let message):
                return StoreDetailEmptyState(
                    title: "가게 정보를 불러오지 못했어요",
                    message: message,
                    actionTitle: "다시 시도"
                )
            }
        }

        return StoreDetailEmptyState(
            title: "가게 정보를 불러오지 못했어요",
            message: resolveErrorMessage(from: error),
            actionTitle: "다시 시도"
        )
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
