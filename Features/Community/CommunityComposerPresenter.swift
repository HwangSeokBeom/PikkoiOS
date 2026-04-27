import Foundation

@MainActor
final class CommunityComposerPresenter: ObservableObject {
    @Published private(set) var viewState = CommunityComposerViewState()

    private let interactor: CommunityComposerInteracting
    private let router: CommunityComposerRouting
    private var hasLoaded = false
    private var draftContext = CommunityComposerDraft.empty
    private let maximumAttachmentCount = 5
    private let maximumAttachmentBytes = 5 * 1024 * 1024

    init(
        interactor: CommunityComposerInteracting,
        router: CommunityComposerRouting
    ) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: CommunityComposerAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await loadInitialContent()
        case .titleChanged(let title):
            clearTransientFeedback()
            draftContext.title = title
            viewState.draftTitle = title
        case .bodyChanged(let body):
            clearTransientFeedback()
            draftContext.body = body
            viewState.draftBody = body
        case .categoryTapped(let categoryID):
            clearTransientFeedback()
            viewState.selectedCategoryID = categoryID
            draftContext.categoryTitle = selectedCategoryTitle(for: categoryID)
        case .attachmentsUploadRequested(let files):
            await uploadAttachments(files)
        case .attachmentPreparationFailed(let message):
            viewState.attachmentUploadErrorMessage = message
        case .attachmentRemoved(let path):
            clearTransientFeedback()
            draftContext.attachments.removeAll { $0.path == path }
            syncAttachmentState()
        case .submitTapped:
            await submitPost()
        }
    }

    private func loadInitialContent() async {
        viewState.isLoading = true
        viewState.errorMessage = nil
        viewState.serverValidationMessage = nil
        viewState.infoMessage = nil
        viewState.attachmentUploadErrorMessage = nil

        do {
            let content = try await interactor.loadInitialContent()
            apply(content: content)
            hasLoaded = true
        } catch {
            viewState.hasLoadedContent = false
            viewState.errorMessage = error.localizedDescription
        }

        viewState.isLoading = false
    }

    private func apply(content: CommunityComposerContent) {
        viewState.mode = content.mode
        viewState.navigationTitle = content.navigationTitle
        viewState.eyebrow = content.eyebrow
        viewState.heroTitle = content.title
        viewState.heroMessage = content.message
        viewState.categoryOptions = content.categoryOptions
        viewState.selectedCategoryID = content.selectedCategoryID
        draftContext = content.initialDraft
        viewState.draftTitle = content.initialDraft.title
        viewState.draftBody = content.initialDraft.body
        viewState.linkedStoreTitle = content.initialDraft.store?.name
        syncAttachmentState()
        viewState.titlePlaceholder = content.titlePlaceholder
        viewState.bodyPlaceholder = content.bodyPlaceholder
        viewState.footerTitle = content.footerTitle
        viewState.footerMessage = content.footerMessage
        viewState.submitTitle = content.submitTitle
        viewState.hasLoadedContent = true
    }

    private func uploadAttachments(_ files: [CommunityPostUploadFile]) async {
        guard !viewState.isUploadingAttachments else {
            return
        }

        guard !files.isEmpty else {
            return
        }

        guard draftContext.attachments.count + files.count <= maximumAttachmentCount else {
            viewState.attachmentUploadErrorMessage = "첨부 파일은 최대 \(maximumAttachmentCount)개까지 올릴 수 있어요."
            return
        }

        guard files.allSatisfy({ $0.data.count <= maximumAttachmentBytes }) else {
            viewState.attachmentUploadErrorMessage = "첨부 파일은 1개당 5MB 이하만 업로드할 수 있어요."
            return
        }

        viewState.isUploadingAttachments = true
        viewState.attachmentUploadErrorMessage = nil
        viewState.errorMessage = nil
        viewState.serverValidationMessage = nil

        do {
            let uploadedPaths = try await interactor.uploadAttachments(files)
            mergeAttachments(with: uploadedPaths)
            syncAttachmentState()
            viewState.infoMessage = "첨부 파일 \(uploadedPaths.count)개를 업로드했어요."
        } catch {
            viewState.attachmentUploadErrorMessage = resolveErrorMessage(from: error)
            Logger.shared.warning("Community attachment upload failed: \(error.localizedDescription)")
        }

        viewState.isUploadingAttachments = false
    }

    private func submitPost() async {
        guard !viewState.isSubmitting else {
            return
        }

        guard !viewState.isUploadingAttachments else {
            viewState.errorMessage = "첨부 파일 업로드가 끝난 뒤 저장할 수 있어요."
            return
        }

        if let attachmentUploadErrorMessage = viewState.attachmentUploadErrorMessage {
            viewState.errorMessage = attachmentUploadErrorMessage
            return
        }

        guard let category = selectedCategoryTitle() else {
            viewState.errorMessage = "카테고리를 선택해 주세요."
            return
        }

        guard viewState.isSubmitEnabled else {
            viewState.errorMessage = "제목과 본문을 모두 입력해 주세요."
            return
        }

        viewState.isSubmitting = true
        viewState.errorMessage = nil
        viewState.serverValidationMessage = nil
        viewState.infoMessage = nil

        do {
            #if DEBUG
            Logger.shared.debug("[CommunityCreate] request started")
            #endif
            let createdPost = try await interactor.submitPost(
                draft: CommunityComposerDraft(
                    title: viewState.draftTitle,
                    body: viewState.draftBody,
                    categoryTitle: category,
                    store: draftContext.store,
                    attachments: draftContext.attachments,
                    latitude: draftContext.latitude,
                    longitude: draftContext.longitude
                )
            )
            #if DEBUG
            Logger.shared.debug("[CommunityCreate] success postID=\(createdPost.summary.id)")
            #endif
            viewState.submittedPostID = createdPost.summary.id
            viewState.infoMessage = successMessage
            router.routeToPostDetail(postID: createdPost.summary.id)
        } catch {
            let message = resolveErrorMessage(from: error)
            if case .some(.validation) = error as? CommunityComposerFeatureError {
                viewState.serverValidationMessage = message
            }
            viewState.errorMessage = message
        }

        viewState.isSubmitting = false
    }

    private func mergeAttachments(with uploadedPaths: [String]) {
        var existing = Set(draftContext.attachments.map(\.path))

        for path in uploadedPaths where existing.insert(path).inserted {
            draftContext.attachments.append(.init(path: path))
        }
    }

    private func syncAttachmentState() {
        viewState.attachmentPaths = draftContext.attachments.map(\.path)
        viewState.attachmentCount = viewState.attachmentPaths.count
    }

    private func selectedCategoryTitle() -> String? {
        guard let selectedCategoryID = viewState.selectedCategoryID else {
            return nil
        }

        return selectedCategoryTitle(for: selectedCategoryID)
    }

    private func selectedCategoryTitle(for categoryID: String) -> String? {
        viewState.categoryOptions.first(where: { $0.id == categoryID })?.title
    }

    private func clearTransientFeedback() {
        viewState.errorMessage = nil
        viewState.serverValidationMessage = nil
        viewState.infoMessage = nil
        viewState.submittedPostID = nil
    }

    private var successMessage: String {
        switch viewState.mode {
        case .create:
            return "게시글을 등록했어요."
        case .edit:
            return "게시글을 저장했어요."
        }
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
