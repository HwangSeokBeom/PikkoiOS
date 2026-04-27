import Foundation

enum ChatScreenMode: Equatable {
    case roomList
    case roomDetail
}

struct ChatRoomRowViewState: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let timeText: String
    let avatarPath: String?
}

struct ChatMessageRowViewState: Equatable, Identifiable {
    let id: String
    let content: String
    let timeText: String
    let senderName: String
    let isMine: Bool
}

struct ChatViewState: Equatable {
    var mode: ChatScreenMode = .roomList
    var title = "채팅"
    var rooms: [ChatRoomRowViewState] = []
    var messages: [ChatMessageRowViewState] = []
    var messageText = ""
    var selectedRoomID: String?
    var isLoading = true
    var isRefreshing = false
    var isSending = false
    var errorMessage: String?
    var emptyTitle: String?
    var emptyMessage: String?
    var primaryActionTitle: String?
    var requiresAuthentication = false
    var isExternalDetailPresentation = false

    var showsEmptyState: Bool {
        !isLoading && mode == .roomList && rooms.isEmpty && emptyTitle != nil
    }

    var showsDetailEmptyState: Bool {
        !isLoading && mode == .roomDetail && messages.isEmpty && emptyTitle != nil
    }

    var canSend: Bool {
        selectedRoomID != nil
            && !isLoading
            && !isSending
            && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var showsInternalBackButton: Bool {
        mode == .roomDetail && !isExternalDetailPresentation
    }
}
