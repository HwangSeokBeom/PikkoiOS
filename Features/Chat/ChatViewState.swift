import Foundation

enum ChatPresentationKind: String {
    case globalSheet
    case profileStack
    case `internal`
}

enum ChatScreenMode: Equatable {
    case roomList
    case roomDetail
}

enum ChatRoomRowSection: Equatable {
    case storeInquiry
    case general
}

struct ChatRoomRowViewState: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let timeText: String
    let avatarPath: String?
    let section: ChatRoomRowSection
}

struct ChatMessageRowViewState: Equatable, Identifiable {
    let id: String
    let dateText: String?
    let content: String
    let filePaths: [String]
    let timeText: String
    let senderName: String
    let isMine: Bool
    let sendStatus: ChatSendStatus

    var statusText: String? {
        switch sendStatus {
        case .sending:
            return "전송 중"
        case .failed:
            return "전송 실패"
        case .sent:
            return nil
        }
    }
}

enum ChatScrollTarget: Equatable {
    case bottom
    case message(id: String)
}

struct ChatScrollCommand: Equatable, Identifiable {
    let id: Int
    let target: ChatScrollTarget
    let reason: String
    let animated: Bool
}

struct ChatViewState: Equatable {
    var mode: ChatScreenMode = .roomList
    var title = "채팅"
    var rooms: [ChatRoomRowViewState] = []
    var messages: [ChatMessageRowViewState] = []
    var messageText = ""
    var attachedFilePaths: [String] = []
    var selectedRoomID: String?
    var isLoading = true
    var isRefreshing = false
    var isSending = false
    var isUploadingFiles = false
    var errorMessage: String?
    var emptyTitle: String?
    var emptyMessage: String?
    var primaryActionTitle: String?
    var requiresAuthentication = false
    var isExternalDetailPresentation = false
    var scrollCommand: ChatScrollCommand?
    var showsNewMessageIndicator = false
    var newMessageCount = 0

    var showsEmptyState: Bool {
        !isLoading && mode == .roomList && rooms.isEmpty && emptyTitle != nil
    }

    var showsDetailEmptyState: Bool {
        !isLoading && mode == .roomDetail && messages.isEmpty && emptyTitle != nil
    }

    var canSend: Bool {
        selectedRoomID != nil
            && !isSending
            && !isUploadingFiles
            && (
                !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !attachedFilePaths.isEmpty
            )
    }

    var showsInternalBackButton: Bool {
        mode == .roomDetail && !isExternalDetailPresentation
    }
}
