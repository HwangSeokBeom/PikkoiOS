import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CommunityComposerView: View {
    @ObservedObject var presenter: CommunityComposerPresenter
    @State private var selectedAttachmentItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack {
            PikkoColor.background
                .ignoresSafeArea()

            if presenter.viewState.isLoading && !presenter.viewState.hasLoadedContent {
                LoadingView(message: "작성 화면을 준비하고 있어요")
                    .padding(PikkoSpacing.xl)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PikkoSpacing.xl) {
                        heroCard
                        categorySection
                        linkedContextCard
                        attachmentSection
                        titleField
                        bodyEditor

                        if let infoMessage = presenter.viewState.infoMessage {
                            ToastView(message: infoMessage, tone: .success)
                        } else if let serverValidationMessage = presenter.viewState.serverValidationMessage {
                            ToastView(message: serverValidationMessage, tone: .warning)
                        }

                        if let submittedPostID = presenter.viewState.submittedPostID {
                            submittedPostCard(postID: submittedPostID)
                        }

                        footerCard
                    }
                    .padding(.horizontal, PikkoSpacing.xl)
                    .padding(.top, PikkoSpacing.xl)
                    .padding(.bottom, PikkoSpacing.xxl + RootTabBarMetrics.scrollContentBottomInset)
                }
                .safeAreaInset(edge: .bottom) {
                    ctaBar
                        .padding(.horizontal, PikkoSpacing.xl)
                        .padding(.top, PikkoSpacing.md)
                        .padding(.bottom, PikkoSpacing.lg + RootTabBarMetrics.scrollContentBottomInset)
                        .background(
                            LinearGradient(
                                colors: [
                                    PikkoColor.background.opacity(0),
                                    PikkoColor.background.opacity(0.92),
                                    PikkoColor.background
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
        .navigationTitle(presenter.viewState.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text(presenter.viewState.eyebrow)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.accentStrong)

            Text(presenter.viewState.heroTitle)
                .font(PikkoTypography.hero)
                .foregroundStyle(PikkoColor.primaryText)

            Text(presenter.viewState.heroMessage)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)

            Text(modeBadgeTitle)
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.accentStrong)
                .padding(.horizontal, PikkoSpacing.sm)
                .padding(.vertical, PikkoSpacing.xs)
                .background(PikkoColor.surfaceMuted)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    @ViewBuilder
    private var linkedContextCard: some View {
        if presenter.viewState.linkedStoreTitle != nil || presenter.viewState.attachmentCount > 0 {
            VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                if let linkedStoreTitle = presenter.viewState.linkedStoreTitle {
                    Label(linkedStoreTitle, systemImage: "storefront.fill")
                        .font(PikkoTypography.bodyStrong)
                        .foregroundStyle(PikkoColor.primaryText)
                }

                if presenter.viewState.attachmentCount > 0 {
                    Label("첨부 \(presenter.viewState.attachmentCount)개", systemImage: "photo.on.rectangle.angled")
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PikkoSpacing.lg)
            .background(PikkoColor.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            SectionHeader(
                title: "카테고리",
                subtitle: "작성 API 전에도 create 모드 초기 상태를 확인할 수 있어요"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PikkoSpacing.xs) {
                    ForEach(presenter.viewState.categoryOptions) { option in
                        TagChip(
                            title: option.title,
                            systemImage: option.systemImage,
                            isSelected: presenter.viewState.selectedCategoryID == option.id,
                            appearance: .subtle,
                            action: {
                                Task { await presenter.send(.categoryTapped(option.id)) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            SectionHeader(
                title: "첨부 파일",
                subtitle: "이미지나 영상을 최대 5개까지 올릴 수 있어요"
            )

            PhotosPicker(
                selection: Binding(
                    get: { selectedAttachmentItems },
                    set: { newValue in
                        selectedAttachmentItems = newValue
                        Task {
                            await handleAttachmentSelection(newValue)
                        }
                    }
                ),
                maxSelectionCount: 5,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .automatic
            ) {
                HStack(spacing: PikkoSpacing.sm) {
                    Image(systemName: "paperclip.circle.fill")
                    Text(presenter.viewState.isUploadingAttachments ? "업로드 중..." : "파일 선택")
                }
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.accentStrong)
                .padding(.horizontal, PikkoSpacing.md)
                .frame(height: 44)
                .background(PikkoColor.surfaceMuted)
                .overlay {
                    RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                        .stroke(PikkoColor.accent.opacity(0.28), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
            }
            .disabled(presenter.viewState.isUploadingAttachments || presenter.viewState.isSubmitting)

            if presenter.viewState.isUploadingAttachments {
                LoadingView(message: "첨부 파일 업로드 중")
            }

            if !presenter.viewState.attachmentPaths.isEmpty {
                VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
                    Text("업로드된 첨부 \(presenter.viewState.attachmentCount)개")
                        .font(PikkoTypography.caption)
                        .foregroundStyle(PikkoColor.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PikkoSpacing.xs) {
                            ForEach(presenter.viewState.attachmentPaths, id: \.self) { path in
                                AttachmentToken(path: path) {
                                    Task { await presenter.send(.attachmentRemoved(path)) }
                                }
                            }
                        }
                    }
                }
            }

            if let attachmentUploadErrorMessage = presenter.viewState.attachmentUploadErrorMessage {
                ToastView(message: attachmentUploadErrorMessage, tone: .warning)
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text("제목")
                .font(PikkoTypography.cardTitle)
                .foregroundStyle(PikkoColor.primaryText)

            TextField(
                presenter.viewState.titlePlaceholder,
                text: Binding(
                    get: { presenter.viewState.draftTitle },
                    set: { value in
                        Task { await presenter.send(.titleChanged(value)) }
                    }
                )
            )
            .font(PikkoTypography.body)
            .foregroundStyle(PikkoColor.primaryText)
            .padding(.horizontal, PikkoSpacing.md)
            .frame(height: 52)
            .background(.white)
            .overlay {
                RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous)
                    .stroke(PikkoColor.accent.opacity(0.25), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.hero, style: .continuous))
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text("본문")
                .font(PikkoTypography.cardTitle)
                .foregroundStyle(PikkoColor.primaryText)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .fill(Color.white)

                RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous)
                    .stroke(PikkoColor.accent.opacity(0.25), lineWidth: 1)

                TextEditor(
                    text: Binding(
                        get: { presenter.viewState.draftBody },
                        set: { value in
                            Task { await presenter.send(.bodyChanged(value)) }
                        }
                    )
                )
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.primaryText)
                .padding(.horizontal, PikkoSpacing.sm)
                .padding(.vertical, PikkoSpacing.sm)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220)

                if presenter.viewState.draftBody.isEmpty {
                    Text(presenter.viewState.bodyPlaceholder)
                        .font(PikkoTypography.body)
                        .foregroundStyle(PikkoColor.tertiaryText)
                        .padding(.horizontal, PikkoSpacing.lg)
                        .padding(.vertical, PikkoSpacing.lg)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 220)
        }
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.sm) {
            Text(presenter.viewState.footerTitle)
                .font(PikkoTypography.cardTitle)
                .foregroundStyle(PikkoColor.primaryText)

            Text(presenter.viewState.footerMessage)
                .font(PikkoTypography.body)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
    }

    private var ctaBar: some View {
        VStack(spacing: PikkoSpacing.sm) {
            if presenter.viewState.serverValidationMessage == nil,
               let errorMessage = presenter.viewState.errorMessage {
                ToastView(message: errorMessage, tone: .warning)
            }

            PrimaryButton(
                title: presenter.viewState.submitTitle,
                systemImage: "square.and.arrow.up.fill",
                isLoading: presenter.viewState.isSubmitting,
                isEnabled: presenter.viewState.isSubmitEnabled,
                action: {
                    Task { await presenter.send(.submitTapped) }
                }
            )
        }
    }

    private func submittedPostCard(postID: String) -> some View {
        VStack(alignment: .leading, spacing: PikkoSpacing.xs) {
            Text("생성된 게시글")
                .font(PikkoTypography.captionStrong)
                .foregroundStyle(PikkoColor.accentStrong)

            Text(postID)
                .font(PikkoTypography.bodyStrong)
                .foregroundStyle(PikkoColor.primaryText)

            Text("다음 턴에서 상세 복귀나 피드 갱신에 이 postID를 바로 사용할 수 있어요.")
                .font(PikkoTypography.caption)
                .foregroundStyle(PikkoColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PikkoSpacing.lg)
        .background(PikkoColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PikkoRadius.card, style: .continuous))
        .pikkoShadow(PikkoShadow.card)
    }

    private var modeBadgeTitle: String {
        switch presenter.viewState.mode {
        case .create:
            return "작성 모드"
        case .edit:
            return "수정 모드"
        }
    }
}

private extension CommunityComposerView {
    @MainActor
    func handleAttachmentSelection(_ items: [PhotosPickerItem]) async {
        defer {
            selectedAttachmentItems = []
        }

        guard !items.isEmpty else { return }

        var uploadFiles: [CommunityPostUploadFile] = []
        uploadFiles.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            guard let preparedFile = await prepareUploadFile(from: item, index: index) else {
                await presenter.send(.attachmentPreparationFailed("선택한 파일을 읽지 못했어요. 다시 시도해 주세요."))
                return
            }
            uploadFiles.append(preparedFile)
        }

        await presenter.send(.attachmentsUploadRequested(uploadFiles))
    }

    func prepareUploadFile(
        from item: PhotosPickerItem,
        index: Int
    ) async -> CommunityPostUploadFile? {
        guard let rawData = try? await item.loadTransferable(type: Data.self),
              !rawData.isEmpty else {
            return nil
        }

        let contentType = item.supportedContentTypes.first
        let baseName = "community-\(Int(Date().timeIntervalSince1970))-\(index)"

        if contentType?.conforms(to: .image) == true,
           let image = UIImage(data: rawData),
           let jpegData = image.jpegData(compressionQuality: 0.88),
           !jpegData.isEmpty {
            return CommunityPostUploadFile(
                data: jpegData,
                fileName: "\(baseName).jpg",
                mimeType: "image/jpeg"
            )
        }

        let fileExtension = contentType?.preferredFilenameExtension ?? "bin"
        let mimeType = contentType?.preferredMIMEType ?? "application/octet-stream"

        return CommunityPostUploadFile(
            data: rawData,
            fileName: "\(baseName).\(fileExtension)",
            mimeType: mimeType
        )
    }
}

private struct AttachmentToken: View {
    let path: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: PikkoSpacing.xs) {
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .semibold))
            Text((path as NSString).lastPathComponent)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .font(PikkoTypography.caption)
        .foregroundStyle(PikkoColor.secondaryText)
        .padding(.horizontal, PikkoSpacing.sm)
        .frame(height: 32)
        .background(PikkoColor.surfaceElevated)
        .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        let router = CommunityComposerRouter()
        CommunityComposerRootView(
            presenter: CommunityComposerPresenter(
                interactor: PreviewCommunityComposerInteractor(),
                router: router
            ),
            router: router
        )
    }
}

@MainActor
private struct PreviewCommunityComposerInteractor: CommunityComposerInteracting {
    func loadInitialContent() async throws -> CommunityComposerContent {
        .create()
    }

    func uploadAttachments(_ files: [CommunityPostUploadFile]) async throws -> [String] {
        files.enumerated().map { index, _ in
            "/data/posts/preview-\(index).jpg"
        }
    }

    func submitPost(draft: CommunityComposerDraft) async throws -> CommunityPostDetail {
        CommunityDetailContent.fallback(postID: "preview-post").detail
    }
}
