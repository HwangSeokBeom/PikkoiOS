import Foundation

struct CommunityComposerDraft: Equatable, Sendable {
    var title: String
    var body: String
    var categoryTitle: String?
    var store: CommunityComposerRouteStoreReference?
    var attachments: [CommunityComposerRouteAttachment]
    var latitude: Double?
    var longitude: Double?

    static let empty = CommunityComposerDraft(
        title: "",
        body: "",
        categoryTitle: nil,
        store: nil,
        attachments: [],
        latitude: nil,
        longitude: nil
    )

    init(
        title: String,
        body: String,
        categoryTitle: String?,
        store: CommunityComposerRouteStoreReference?,
        attachments: [CommunityComposerRouteAttachment],
        latitude: Double?,
        longitude: Double?
    ) {
        self.title = title
        self.body = body
        self.categoryTitle = categoryTitle
        self.store = store
        self.attachments = attachments
        self.latitude = latitude
        self.longitude = longitude
    }

    init(routeDraft: CommunityComposerInitialDraft) {
        self.init(
            title: routeDraft.title,
            body: routeDraft.body,
            categoryTitle: routeDraft.categoryTitle,
            store: routeDraft.store,
            attachments: routeDraft.attachments,
            latitude: routeDraft.latitude,
            longitude: routeDraft.longitude
        )
    }
}

struct CommunityComposerContent: Equatable {
    let mode: CommunityComposerMode
    let navigationTitle: String
    let eyebrow: String
    let title: String
    let message: String
    let categoryOptions: [CommunityComposerCategoryOption]
    let selectedCategoryID: String?
    let initialDraft: CommunityComposerDraft
    let titlePlaceholder: String
    let bodyPlaceholder: String
    let footerTitle: String
    let footerMessage: String
    let submitTitle: String

    static func create(initialDraft: CommunityComposerDraft = .empty) -> CommunityComposerContent {
        let categoryOptions = buildCategoryOptions(selectedCategoryTitle: initialDraft.categoryTitle)
        let selectedCategoryID = selectedCategoryID(
            from: initialDraft.categoryTitle,
            categoryOptions: categoryOptions
        ) ?? "daily"

        return CommunityComposerContent(
            mode: .create,
            navigationTitle: "작성하기",
            eyebrow: "Community Composer",
            title: "커뮤니티 글을 바로 등록할 수 있어요",
            message: "제목, 본문, 카테고리와 현재 위치를 기준으로 게시글을 등록합니다. 첨부 파일은 먼저 업로드한 뒤 게시글에 연결합니다.",
            categoryOptions: categoryOptions,
            selectedCategoryID: selectedCategoryID,
            initialDraft: initialDraft,
            titlePlaceholder: "제목을 입력해 주세요",
            bodyPlaceholder: "오늘 공유하고 싶은 이야기를 적어 보세요.",
            footerTitle: "현재 범위",
            footerMessage: "첨부 파일 업로드가 끝난 뒤 게시글 저장이 진행됩니다. 수정 모드에서는 기존 첨부 경로를 유지합니다.",
            submitTitle: "등록"
        )
    }

    static func edit(
        postID: String,
        initialDraft: CommunityComposerDraft
    ) -> CommunityComposerContent {
        let categoryOptions = buildCategoryOptions(selectedCategoryTitle: initialDraft.categoryTitle)
        let selectedCategoryID = selectedCategoryID(
            from: initialDraft.categoryTitle,
            categoryOptions: categoryOptions
        )

        return CommunityComposerContent(
            mode: .edit(postID: postID),
            navigationTitle: "수정하기",
            eyebrow: "커뮤니티 글 수정",
            title: "기존 게시글을 그대로 이어서 수정할 수 있어요",
            message: "내용과 첨부 이미지를 확인한 뒤 필요한 부분만 바꿔 저장해 주세요.",
            categoryOptions: categoryOptions,
            selectedCategoryID: selectedCategoryID,
            initialDraft: initialDraft,
            titlePlaceholder: "제목을 수정해 주세요",
            bodyPlaceholder: "게시글 내용을 수정해 보세요.",
            footerTitle: "수정 모드",
            footerMessage: "저장 후 게시글 상세 화면으로 돌아갑니다.",
            submitTitle: "저장"
        )
    }

    private static func buildCategoryOptions(selectedCategoryTitle: String?) -> [CommunityComposerCategoryOption] {
        var options = CommunityComposerCategoryOption.defaultOptions

        guard let selectedCategoryTitle,
              !selectedCategoryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              options.contains(where: { $0.title == selectedCategoryTitle }) == false else {
            return options
        }

        options.insert(
            CommunityComposerCategoryOption(
                id: "custom-\(selectedCategoryTitle)",
                title: selectedCategoryTitle,
                systemImage: "tag.fill"
            ),
            at: 0
        )
        return options
    }

    private static func selectedCategoryID(
        from categoryTitle: String?,
        categoryOptions: [CommunityComposerCategoryOption]
    ) -> String? {
        guard let categoryTitle else {
            return nil
        }

        return categoryOptions.first(where: { $0.title == categoryTitle })?.id
    }
}

struct CommunityComposerCategoryOption: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String?

    static let defaultOptions: [CommunityComposerCategoryOption] = [
        .init(id: "daily", title: "일상", systemImage: "sun.max.fill"),
        .init(id: "pickup", title: "픽업후기", systemImage: "takeoutbag.and.cup.and.straw.fill"),
        .init(id: "question", title: "질문", systemImage: "questionmark.bubble.fill")
    ]
}

enum CommunityComposerFeatureError: Error, Equatable {
    case validation(message: String)
    case authenticationRequired
    case unavailable(message: String)
}

extension CommunityComposerFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .validation(let message), .unavailable(let message):
            return message
        case .authenticationRequired:
            return "로그인 후 게시글을 작성할 수 있어요."
        }
    }
}
