import Foundation

enum ChatSearchScope: Equatable {
    case loadedMessagesOnly
    case localCache

    var noticeText: String {
        switch self {
        case .loadedMessagesOnly:
            return "현재 불러온 메시지에서 검색해요."
        case .localCache:
            return "기기에 저장된 메시지까지 검색해요."
        }
    }
}

struct ChatSearchResult: Equatable, Sendable, Identifiable {
    let id: String
    let messageID: String
    let serverChatID: String?
    let localTemporaryID: String?
    let clientMessageID: String?
    let preview: String
    let matchRanges: [NSRange]
    let createdAt: Date?
    let messageIndex: Int
}

enum ChatSearchEngine {
    static func search(messages: [ChatMessage], query: String) -> [ChatSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }

        return messages.enumerated().compactMap { index, message in
            let ranges = matchRanges(in: message.content, query: normalizedQuery)
            guard !ranges.isEmpty else { return nil }
            return ChatSearchResult(
                id: stableResultID(for: message),
                messageID: message.renderID,
                serverChatID: message.effectiveServerChatID,
                localTemporaryID: message.effectiveLocalTemporaryID,
                clientMessageID: message.clientMessageID,
                preview: message.content,
                matchRanges: ranges,
                createdAt: message.createdAt,
                messageIndex: index
            )
        }
    }

    static func matchRanges(in content: String, query: String) -> [NSRange] {
        guard !content.isEmpty, !query.isEmpty else { return [] }

        var ranges: [NSRange] = []
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let range = content.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<content.endIndex,
                locale: Locale(identifier: "ko_KR")
              ) {
            ranges.append(NSRange(range, in: content))
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func stableResultID(for message: ChatMessage) -> String {
        if let serverID = message.effectiveServerChatID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "server:\(serverID)"
        }
        if let clientID = message.clientMessageID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "client:\(clientID)"
        }
        if let localID = message.effectiveLocalTemporaryID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return "local:\(localID)"
        }
        return "render:\(message.renderID)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

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
    var searchSnippet: String? = nil
}

struct ChatMessageRowViewState: Equatable, Identifiable {
    let id: String
    let dateText: String?
    let content: String
    let searchMatchRanges: [NSRange]
    let filePaths: [String]
    let timeText: String
    let senderName: String
    let isMine: Bool
    let sendStatus: ChatSendStatus
    let isSelectedSearchMatch: Bool

    var statusText: String? {
        switch sendStatus {
        case .queued:
            return "대기 중"
        case .sending, .retrying:
            return "전송 중"
        case .failed, .failedAuth, .recoveryNeeded:
            return "전송 실패"
        case .sent, .recovered:
            return nil
        }
    }
}

struct ChatMessageSearchState: Equatable {
    var isSearchActive = false
    var query = ""
    var matches: [ChatSearchResultViewState] = []
    var selectedMatchIndex: Int?
    var isLoadingSearchExpansion = false
    var searchScope: ChatSearchScope = .loadedMessagesOnly
    var mayHaveOlderUnloadedMessages = true
    var isSearching = false

    var selectedMatch: ChatSearchResultViewState? {
        guard let selectedMatchIndex,
              matches.indices.contains(selectedMatchIndex) else {
            return nil
        }
        return matches[selectedMatchIndex]
    }
}

struct ChatSearchResultViewState: Equatable, Identifiable {
    let id: String
    let messageID: String
    let preview: String
    let matchRanges: [NSRange]
    let createdAt: Date?
    let messageIndex: Int
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
    var isInitialLoading = false
    var isRefreshing = false
    var isLoadingNextPage = false
    var hasMoreRooms = false
    var nextRoomPage: Int?
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
    var roomListSearchQuery = ""
    var roomListSearchResultCount: Int?
    var isSearchActive = false
    var searchQuery = ""
    var searchResults: [ChatSearchResultViewState] = []
    var selectedSearchResultIndex: Int?
    var isSearching = false
    var searchScope: ChatSearchScope = .loadedMessagesOnly
    var searchMayHaveOlderUnloadedMessages = true
    var messageSearch = ChatMessageSearchState()

    var selectedSearchResult: ChatSearchResultViewState? {
        guard let selectedSearchResultIndex,
              searchResults.indices.contains(selectedSearchResultIndex) else {
            return nil
        }
        return searchResults[selectedSearchResultIndex]
    }

    var searchStatusText: String {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return ""
        }
        if isSearching {
            return "검색 중..."
        }
        if searchResults.isEmpty {
            return "검색 결과가 없어요."
        }
        return "\(searchResults.count)개 결과"
    }

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

    var canNavigateSearchResults: Bool {
        searchResults.count > 1
    }

    var searchScopeNoticeText: String {
        searchScope.noticeText
    }
}
