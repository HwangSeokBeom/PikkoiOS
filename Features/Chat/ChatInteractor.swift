import CoreData
import Foundation

struct ChatParticipant: Equatable, Sendable, Identifiable {
    let id: String
    let nick: String
    let profileImagePath: String?
}

enum ChatSendStatus: String, Codable, Equatable, Sendable {
    case sending
    case sent
    case failed
}

struct ChatMessage: Equatable, Sendable, Identifiable {
    let id: String
    let localTemporaryID: String?
    let serverChatID: String?
    let roomID: String
    let content: String
    let createdAt: Date?
    let updatedAt: Date?
    let sender: ChatParticipant
    let filePaths: [String]
    let sendStatus: ChatSendStatus

    init(
        id: String,
        localTemporaryID: String? = nil,
        serverChatID: String? = nil,
        roomID: String,
        content: String,
        createdAt: Date?,
        updatedAt: Date?,
        sender: ChatParticipant,
        filePaths: [String],
        sendStatus: ChatSendStatus = .sent
    ) {
        self.id = id
        self.localTemporaryID = localTemporaryID
        self.serverChatID = serverChatID
        self.roomID = roomID
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sender = sender
        self.filePaths = filePaths
        self.sendStatus = sendStatus
    }

    var effectiveServerChatID: String? {
        serverChatID ?? (id.hasPrefix("local-") ? nil : id)
    }

    var effectiveLocalTemporaryID: String? {
        localTemporaryID ?? (id.hasPrefix("local-") ? id : nil)
    }

    var renderID: String {
        effectiveLocalTemporaryID ?? effectiveServerChatID ?? id
    }

    func replacingIdentity(
        id: String? = nil,
        localTemporaryID: String? = nil,
        serverChatID: String? = nil,
        sendStatus: ChatSendStatus? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: id ?? self.id,
            localTemporaryID: localTemporaryID ?? self.localTemporaryID,
            serverChatID: serverChatID ?? self.serverChatID,
            roomID: roomID,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sender: sender,
            filePaths: filePaths,
            sendStatus: sendStatus ?? self.sendStatus
        )
    }
}

enum ChatMessageMergePolicy {
    static let optimisticMatchInterval: TimeInterval = 10

    static func merged(
        existing messages: [ChatMessage],
        incoming message: ChatMessage,
        currentUserID: String?,
        source: String
    ) -> [ChatMessage] {
        let countBefore = messages.count
        var result = messages

        if let serverID = message.effectiveServerChatID,
           let index = result.firstIndex(where: { $0.effectiveServerChatID == serverID }) {
#if DEBUG
            if ChatDebugOptions.isMergeLoggingEnabled {
                DebugLogDeduplicator.shared.printOnce(
                    key: "ChatMerge.skipDuplicate.\(serverID).\(source)",
                    message: "[ChatMerge] skipDuplicate serverChatId=\(serverID) source=\(source)"
                )
            }
#endif
            result[index] = mergeServerMessage(message, into: result[index])
            let deduped = deduplicated(result, currentUserID: currentUserID)
#if DEBUG
            if ChatDebugOptions.isMergeLoggingEnabled {
                Logger.shared.debug("[ChatMerge] result countBefore=\(countBefore) countAfter=\(deduped.count)")
            }
#endif
            return deduped
        }

        if let serverID = message.effectiveServerChatID,
           let index = result.firstIndex(where: { isOptimistic($0, matching: message, currentUserID: currentUserID) }) {
            let localID = result[index].effectiveLocalTemporaryID ?? message.effectiveLocalTemporaryID ?? "-"
#if DEBUG
            if ChatDebugOptions.isMergeLoggingEnabled {
                DebugLogDeduplicator.shared.printOnce(
                    key: "ChatMerge.replaceOptimistic.\(localID).\(serverID).\(source)",
                    message: "[ChatMerge] replaceOptimistic localTemporaryId=\(localID) serverChatId=\(serverID) source=\(source)"
                )
            }
#endif
            result[index] = mergeServerMessage(message, into: result[index])
            let deduped = deduplicated(result, currentUserID: currentUserID)
#if DEBUG
            if ChatDebugOptions.isMergeLoggingEnabled {
                Logger.shared.debug("[ChatMerge] result countBefore=\(countBefore) countAfter=\(deduped.count)")
            }
#endif
            return deduped
        }

        if let localID = message.effectiveLocalTemporaryID,
           result.contains(where: { $0.effectiveLocalTemporaryID == localID }) {
            let deduped = deduplicated(result, currentUserID: currentUserID)
#if DEBUG
            if ChatDebugOptions.isMergeLoggingEnabled, countBefore != deduped.count {
                Logger.shared.debug("[ChatMerge] result countBefore=\(countBefore) countAfter=\(deduped.count)")
            }
#endif
            return deduped
        }

        result.append(message)
        let deduped = deduplicated(result, currentUserID: currentUserID)
#if DEBUG
        if ChatDebugOptions.isMergeLoggingEnabled, countBefore != deduped.count {
            Logger.shared.debug("[ChatMerge] result countBefore=\(countBefore) countAfter=\(deduped.count)")
        }
#endif
        return deduped
    }

    static func deduplicated(_ messages: [ChatMessage], currentUserID: String?) -> [ChatMessage] {
        var result: [ChatMessage] = []

        for message in sorted(messages) {
            if let serverID = message.effectiveServerChatID {
                if let index = result.firstIndex(where: { $0.effectiveServerChatID == serverID }) {
                    result[index] = mergeServerMessage(message, into: result[index])
                } else {
                    result.removeAll { existing in
                        existing.effectiveServerChatID == nil
                            && isOptimistic(existing, matching: message, currentUserID: currentUserID)
                    }
                    result.append(message)
                }
                continue
            }

            if let localID = message.effectiveLocalTemporaryID,
               result.contains(where: { $0.effectiveLocalTemporaryID == localID }) {
                continue
            }

            if result.contains(where: { server in
                server.effectiveServerChatID != nil
                    && isOptimistic(message, matching: server, currentUserID: currentUserID)
            }) {
                continue
            }

            result.append(message)
        }

        return sorted(result)
    }

    private static func mergeServerMessage(_ serverMessage: ChatMessage, into existing: ChatMessage) -> ChatMessage {
        guard let serverID = serverMessage.effectiveServerChatID else {
            return serverMessage
        }
        return ChatMessage(
            id: serverID,
            localTemporaryID: existing.effectiveLocalTemporaryID ?? serverMessage.effectiveLocalTemporaryID,
            serverChatID: serverID,
            roomID: serverMessage.roomID,
            content: serverMessage.content,
            createdAt: serverMessage.createdAt,
            updatedAt: serverMessage.updatedAt,
            sender: serverMessage.sender,
            filePaths: serverMessage.filePaths,
            sendStatus: .sent
        )
    }

    private static func isOptimistic(_ optimistic: ChatMessage, matching serverMessage: ChatMessage, currentUserID: String?) -> Bool {
        guard optimistic.effectiveServerChatID == nil,
              optimistic.sendStatus == .sending,
              optimistic.sender.id == serverMessage.sender.id,
              optimistic.content == serverMessage.content,
              optimistic.filePaths == serverMessage.filePaths else {
            return false
        }
        if let currentUserID, optimistic.sender.id != currentUserID {
            return false
        }
        let optimisticDate = optimistic.createdAt ?? optimistic.updatedAt
        let serverDate = serverMessage.createdAt ?? serverMessage.updatedAt
        guard let optimisticDate, let serverDate else {
            return true
        }
        return abs(optimisticDate.timeIntervalSince(serverDate)) <= optimisticMatchInterval
    }

    private static func sorted(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted {
            let lhsDate = $0.createdAt ?? .distantPast
            let rhsDate = $1.createdAt ?? .distantPast
            if lhsDate == rhsDate {
                return $0.renderID < $1.renderID
            }
            return lhsDate < rhsDate
        }
    }
}

struct ChatUploadFile: Equatable, Sendable {
    let data: Data
    let fileName: String
    let mimeType: String
}

struct ChatRoom: Equatable, Sendable, Identifiable {
    let id: String
    let createdAt: Date?
    let updatedAt: Date?
    let participants: [ChatParticipant]
    let lastMessage: ChatMessage?
    let storeID: String?
    let storeName: String?
    let opponentID: String?
    let opponentName: String?
    let roomType: String?

    func updating(lastMessage: ChatMessage) -> ChatRoom {
        ChatRoom(
            id: id,
            createdAt: createdAt,
            updatedAt: lastMessage.createdAt ?? updatedAt,
            participants: participants,
            lastMessage: lastMessage,
            storeID: storeID,
            storeName: storeName,
            opponentID: opponentID,
            opponentName: opponentName,
            roomType: roomType
        )
    }

    func applyingStoreContext(storeID: String?, storeName: String?) -> ChatRoom {
        ChatRoom(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            participants: participants,
            lastMessage: lastMessage,
            storeID: storeID ?? self.storeID,
            storeName: storeName ?? self.storeName,
            opponentID: opponentID,
            opponentName: opponentName,
            roomType: roomType
        )
    }
}

struct ChatTargetSummary: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case store
        case user
    }

    let id: String
    let title: String
    let profileImagePath: String?
    let kind: Kind
}

enum ChatTarget: Equatable, Sendable {
    case store(
        storeID: String,
        storeName: String,
        ownerID: String?,
        ownerName: String?,
        ownerProfileImagePath: String?
    )
    case user(
        userID: String,
        nickname: String,
        profileImagePath: String?
    )
    case room(
        roomID: String,
        title: String,
        target: ChatTargetSummary?
    )

    var preferredTitle: String {
        switch self {
        case .store(_, let storeName, _, _, _):
            return storeName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "문의하기"
        case .user(_, let nickname, _):
            return nickname
        case .room(_, let title, _):
            return title
        }
    }
}

enum ChatRoomEntryPoint: Equatable, Sendable {
    case storeDetail
    case storeScopedChatList
    case chatList
    case userProfile
}

struct ChatRoomContext: Equatable, Sendable {
    let entryPoint: ChatRoomEntryPoint
    let roomID: String
    let opponentID: String?
    let storeID: String?
    let storeName: String?
    let displayTitle: String
    let canUseStoreScopedTitle: Bool
    let hasRoomIDCollision: Bool
    let collidingStoreIDs: [String]

    var localCacheScope: ChatRoomScope {
        ChatRoomScope(roomID: roomID, storeID: storeID, opponentID: opponentID)
    }
}

struct ChatRoomScope: Equatable, Sendable {
    let roomID: String
    let storeID: String?
    let opponentID: String?

    var localCacheKey: String {
        [
            "room:\(roomID)",
            "store:\(storeID ?? "-")",
            "opponent:\(opponentID ?? "-")"
        ].joined(separator: "|")
    }

    var isStoreInquiry: Bool {
        storeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
    }
}

struct ChatLocalConversationSummary: Equatable, Sendable, Identifiable {
    let id: String
    let serverRoomID: String
    let localCacheKey: String
    let storeID: String
    let storeName: String
    let opponentID: String
    let lastLocalMessage: ChatMessage?
    let updatedAt: Date

    var scope: ChatRoomScope {
        ChatRoomScope(roomID: serverRoomID, storeID: storeID, opponentID: opponentID)
    }
}

enum ChatRoomContextPolicy {
    static let sendsStoreIDInCreateRoomRequest = true
}

struct CreateChatRoomRequestDTO: Encodable, Sendable {
    let opponentID: String
    let storeID: String?

    private enum CodingKeys: String, CodingKey {
        case opponentID = "opponent_id"
        case storeID = "store_id"
    }

    init(opponentID: String, storeID: String?) {
        self.opponentID = opponentID
        self.storeID = storeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(opponentID: String) {
        self.init(opponentID: opponentID, storeID: nil)
    }

    init(mode: ChatRoomCreationMode) {
        self.init(opponentID: mode.opponentID, storeID: mode.storeID)
    }
}

enum ChatRoomCreationMode: Equatable, Sendable {
    case storeInquiry(storeID: String, opponentID: String, storeName: String)
    case user(opponentID: String)

    var endpoint: String {
        "/v1/chats"
    }

    var name: String {
        switch self {
        case .storeInquiry:
            return "store_inquiry"
        case .user:
            return "opponent_id"
        }
    }

    var requestBodyKeys: [String] {
        switch self {
        case .storeInquiry:
            return ["opponent_id", "store_id"]
        case .user:
            return ["opponent_id"]
        }
    }

    var opponentID: String {
        switch self {
        case .storeInquiry(_, let opponentID, _),
             .user(let opponentID):
            return opponentID
        }
    }

    var storeID: String? {
        guard case .storeInquiry(let storeID, _, _) = self else {
            return nil
        }
        return storeID
    }

    var storeName: String? {
        guard case .storeInquiry(_, _, let storeName) = self else {
            return nil
        }
        return storeName
    }

    var debugDescription: String {
        let normalizedStoreID = storeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedOpponentID = opponentID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedStoreName = storeName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return "mode=\(name) endpoint=POST \(endpoint) requestBodyKeys=\(requestBodyKeys.joined(separator: ",")) storeIdExists=\(normalizedStoreID != nil) opponentIdExists=\(normalizedOpponentID != nil) storeName=\(normalizedStoreName ?? "-") storeId=\(normalizedStoreID ?? "-") opponentId=\(normalizedOpponentID ?? "-")"
    }
}

struct SendChatMessageRequestDTO: Encodable, Sendable {
    let content: String
    let files: [String]
}

struct ChatMessageDTO: Decodable, Sendable {
    let chatID: String
    let roomID: String
    let content: String
    let createdAt: String?
    let updatedAt: String?
    let sender: UserInfoResponseDTO
    let files: [String]

    private enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case roomID = "room_id"
        case content
        case createdAt
        case updatedAt
        case sender
        case files
    }
}

struct ChatRoomDTO: Decodable, Sendable {
    let roomID: String
    let createdAt: String?
    let updatedAt: String?
    let participants: [UserInfoResponseDTO]
    let lastChat: ChatMessageDTO?
    let storeID: String?
    let storeName: String?
    let opponentID: String?
    let opponentName: String?
    let roomType: String?
    let store: ChatRoomStoreDTO?

    private enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case createdAt
        case updatedAt
        case participants
        case lastChat
        case lastMessage = "last_message"
        case storeID = "store_id"
        case storeName = "store_name"
        case opponentID = "opponent_id"
        case opponentName = "opponent_name"
        case roomType = "room_type"
        case store
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID = try container.decode(String.self, forKey: .roomID)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        participants = try container.decodeIfPresent([UserInfoResponseDTO].self, forKey: .participants) ?? []
        lastChat = try container.decodeIfPresent(ChatMessageDTO.self, forKey: .lastChat)
            ?? container.decodeIfPresent(ChatMessageDTO.self, forKey: .lastMessage)
        storeID = try container.decodeIfPresent(String.self, forKey: .storeID)
        storeName = try container.decodeIfPresent(String.self, forKey: .storeName)
        opponentID = try container.decodeIfPresent(String.self, forKey: .opponentID)
        opponentName = try container.decodeIfPresent(String.self, forKey: .opponentName)
        roomType = try container.decodeIfPresent(String.self, forKey: .roomType)
        store = try container.decodeIfPresent(ChatRoomStoreDTO.self, forKey: .store)
    }
}

struct ChatRoomStoreDTO: Decodable, Sendable {
    let storeID: String?
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case id
        case name
        case storeName = "store_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storeID = try container.decodeIfPresent(String.self, forKey: .storeID)
            ?? (try container.decodeIfPresent(String.self, forKey: .id))
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? (try container.decodeIfPresent(String.self, forKey: .storeName))
    }
}

struct ChatRoomListResponseDTO: Decodable, Sendable {
    let data: [ChatRoomDTO]
}

struct ChatMessageListResponseDTO: Decodable, Sendable {
    let data: [ChatMessageDTO]
}

struct ChatFileResponseDTO: Decodable, Sendable {
    let files: [String]
}

protocol ChatRemoteDataSourceProtocol: Sendable {
    func fetchChatRooms() async throws -> ChatRoomListResponseDTO
    func createOrFetchChatRoom(mode: ChatRoomCreationMode) async throws -> ChatRoomDTO
    func fetchMessages(roomID: String, next: String?) async throws -> ChatMessageListResponseDTO
    func sendMessage(roomID: String, content: String, files: [String]) async throws -> ChatMessageDTO
    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> ChatFileResponseDTO
}

struct ChatRemoteDataSource: ChatRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchChatRooms() async throws -> ChatRoomListResponseDTO {
        let endpoint = Endpoint<ChatRoomListResponseDTO>(
            path: "/v1/chats",
            method: .get,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func createOrFetchChatRoom(mode: ChatRoomCreationMode) async throws -> ChatRoomDTO {
        let requestDTO = CreateChatRoomRequestDTO(mode: mode)
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                requestDTO
            )
        )
        Logger.shared.debug("[ChatRepository] createOrFetchRoom request \(mode.debugDescription)")
        let endpoint = Endpoint<ChatRoomDTO>(
            path: "/v1/chats",
            method: .post,
            body: body,
            authorizationPolicy: .accessToken
        )
        do {
            let response = try await apiClient.execute(endpoint)
            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom response roomId=\(response.roomID) \(mode.debugDescription)"
            )
            return response
        } catch {
            Logger.shared.warning(
                "[ChatRepository] createOrFetchRoom failed \(mode.debugDescription) requestBodyValueExists={opponent_id:\(!mode.opponentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),store_id:\(mode.storeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil)} error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    func fetchMessages(roomID: String, next: String?) async throws -> ChatMessageListResponseDTO {
        let query = next.map { [URLQueryItem(name: "next", value: $0)] } ?? []
        let endpoint = Endpoint<ChatMessageListResponseDTO>(
            path: "/v1/chats/\(roomID)",
            method: .get,
            query: query,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func sendMessage(roomID: String, content: String, files: [String] = []) async throws -> ChatMessageDTO {
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                SendChatMessageRequestDTO(content: content, files: files)
            )
        )
        let endpoint = Endpoint<ChatMessageDTO>(
            path: "/v1/chats/\(roomID)",
            method: .post,
            body: body,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> ChatFileResponseDTO {
        var multipartBuilder = MultipartFormDataBuilder()
        for file in files {
            multipartBuilder.addFile(
                fieldName: "files",
                fileName: file.fileName,
                mimeType: file.mimeType,
                fileData: file.data
            )
        }

        let endpoint = Endpoint<ChatFileResponseDTO>(
            path: "/v1/chats/\(roomID)/files",
            method: .post,
            body: multipartBuilder.build(),
            timeout: .upload,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }
}

protocol ChatRepository: Sendable {
    func fetchChatRooms() async throws -> [ChatRoom]
    func createOrFetchChatRoom(mode: ChatRoomCreationMode) async throws -> ChatRoom
    func fetchMessages(roomID: String, next: String?) async throws -> [ChatMessage]
    func sendMessage(roomID: String, content: String, files: [String]) async throws -> ChatMessage
    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> [String]
}

struct DefaultChatRepository: ChatRepository {
    private let remoteDataSource: any ChatRemoteDataSourceProtocol
    private let mapper: ChatMapper

    init(remoteDataSource: any ChatRemoteDataSourceProtocol, mapper: ChatMapper) {
        self.remoteDataSource = remoteDataSource
        self.mapper = mapper
    }

    func fetchChatRooms() async throws -> [ChatRoom] {
        try await remoteDataSource.fetchChatRooms().data.map(mapper.mapRoom)
    }

    func createOrFetchChatRoom(mode: ChatRoomCreationMode) async throws -> ChatRoom {
        let response = try await remoteDataSource.createOrFetchChatRoom(mode: mode)
        return mapper.mapRoom(response)
    }

    func fetchMessages(roomID: String, next: String?) async throws -> [ChatMessage] {
        try await remoteDataSource.fetchMessages(roomID: roomID, next: next).data.map(mapper.mapMessage)
    }

    func sendMessage(roomID: String, content: String, files: [String]) async throws -> ChatMessage {
        let response = try await remoteDataSource.sendMessage(roomID: roomID, content: content, files: files)
        return mapper.mapMessage(response)
    }

    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> [String] {
        let response = try await remoteDataSource.uploadFiles(roomID: roomID, files: files)
        return response.files
    }
}

struct ChatMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let dateParser: DateParser

    init(
        fileURLResolver: any AuthorizedFileURLResolving,
        dateParser: DateParser = DateParser()
    ) {
        self.fileURLResolver = fileURLResolver
        self.dateParser = dateParser
    }

    func mapRoom(_ dto: ChatRoomDTO) -> ChatRoom {
        let storeID = dto.store?.storeID?.nilIfEmpty ?? dto.storeID?.nilIfEmpty
        let storeName = dto.store?.name?.nilIfEmpty ?? dto.storeName?.nilIfEmpty
        let opponentID = dto.opponentID?.nilIfEmpty
        let opponentName = dto.opponentName?.nilIfEmpty
        let participants = dto.participants.isEmpty && (opponentID != nil || opponentName != nil)
            ? [
                ChatParticipant(
                    id: opponentID ?? "opponent",
                    nick: opponentName ?? "채팅",
                    profileImagePath: nil
                )
            ]
            : dto.participants.map(mapParticipant)
        return ChatRoom(
            id: dto.roomID,
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601),
            participants: participants,
            lastMessage: dto.lastChat.map(mapMessage),
            storeID: storeID,
            storeName: storeName,
            opponentID: opponentID,
            opponentName: opponentName,
            roomType: dto.roomType?.nilIfEmpty
        )
    }

    func mapMessage(_ dto: ChatMessageDTO) -> ChatMessage {
        ChatMessage(
            id: dto.chatID,
            serverChatID: dto.chatID,
            roomID: dto.roomID,
            content: dto.content,
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601),
            sender: mapParticipant(dto.sender),
            filePaths: dto.files.compactMap(resolvePath)
        )
    }

    private func mapParticipant(_ dto: UserInfoResponseDTO) -> ChatParticipant {
        ChatParticipant(
            id: dto.userID,
            nick: dto.nick,
            profileImagePath: dto.profileImage.flatMap(resolvePath)
        )
    }

    private func resolvePath(_ path: String) -> String? {
        guard let resolved = try? fileURLResolver.resolveURL(from: path) else {
            return nil
        }
        return resolved.absoluteString
    }
}

struct ChatRoomStoreContext: Codable, Equatable, Sendable {
    let roomID: String
    let storeID: String
    let storeName: String
    let opponentID: String
    let updatedAt: Date
}

protocol ChatRoomStoreContextCaching: Sendable {
    func context(for roomID: String) -> ChatRoomStoreContext?
    func context(forStoreID storeID: String) -> ChatRoomStoreContext?
    func contexts(for roomID: String) -> [ChatRoomStoreContext]
    func allContexts() -> [ChatRoomStoreContext]
    @discardableResult
    func save(_ context: ChatRoomStoreContext) -> Bool
}

final class UserDefaultsChatRoomStoreContextCache: ChatRoomStoreContextCaching, @unchecked Sendable {
    static let shared = UserDefaultsChatRoomStoreContextCache()

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func context(for roomID: String) -> ChatRoomStoreContext? {
        let matches = loadContexts().values.filter { $0.roomID == roomID }
        guard matches.count == 1 else {
            if matches.count > 1 {
                let storeIDs = matches.map(\.storeID).joined(separator: ",")
#if DEBUG
                DebugLogDeduplicator.shared.printOnce(
                    key: "ChatRoomContext.multipleStoreScopesShareServerRoom.\(roomID).\(storeIDs)",
                    level: .info,
                    message: "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(roomID) storeCount=\(matches.count) storeIds=\(storeIDs)"
                )
#else
                Logger.shared.info(
                    "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(roomID) storeCount=\(matches.count) storeIds=\(storeIDs)"
                )
#endif
            }
            return nil
        }

        return matches.first
    }

    func context(forStoreID storeID: String) -> ChatRoomStoreContext? {
        loadContexts()[storeID]
    }

    func contexts(for roomID: String) -> [ChatRoomStoreContext] {
        loadContexts().values
            .filter { $0.roomID == roomID }
            .sorted { $0.storeID < $1.storeID }
    }

    func allContexts() -> [ChatRoomStoreContext] {
        loadContexts().values.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.storeID < $1.storeID
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    @discardableResult
    func save(_ context: ChatRoomStoreContext) -> Bool {
        var contexts = loadContexts()
        if let existing = contexts[context.storeID],
           existing.roomID != context.roomID {
            Logger.shared.warning(
                "[ChatRoomContext] storeId remapped oldRoomId=\(existing.roomID) newRoomId=\(context.roomID) storeId=\(context.storeID)"
            )
        }

        if contexts.values.contains(where: { $0.roomID == context.roomID && $0.storeID != context.storeID }) {
            let mappedStoreIDs = (contexts.values.filter { $0.roomID == context.roomID }.map(\.storeID) + [context.storeID])
                .removingDuplicates()
                .joined(separator: ",")
#if DEBUG
            DebugLogDeduplicator.shared.printOnce(
                key: "ChatRoomContext.multipleStoreScopesShareServerRoom.\(context.roomID).\(mappedStoreIDs)",
                level: .info,
                message: "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(context.roomID) storeCount=\(mappedStoreIDs.split(separator: ",").count) storeIds=\(mappedStoreIDs)"
            )
#else
            Logger.shared.info(
                "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(context.roomID) storeCount=\(mappedStoreIDs.split(separator: ",").count) storeIds=\(mappedStoreIDs)"
            )
#endif
        }

        contexts[context.storeID] = context
        saveContexts(contexts)
        return true
    }

    private func loadContexts() -> [String: ChatRoomStoreContext] {
        guard let data = userDefaults.data(forKey: indexKey),
              let contexts = try? JSONDecoder().decode([String: ChatRoomStoreContext].self, from: data) else {
            return migrateLegacyContextsIfNeeded()
        }

        return contexts
    }

    private func migrateLegacyContextsIfNeeded() -> [String: ChatRoomStoreContext] {
        let legacyPrefix = "chatRoomStoreContext."
        var contexts: [String: ChatRoomStoreContext] = [:]

        for legacyIndexKey in legacyIndexKeys {
            guard let data = userDefaults.data(forKey: legacyIndexKey),
                  let indexedContexts = try? JSONDecoder().decode([String: ChatRoomStoreContext].self, from: data) else {
                continue
            }
            contexts.merge(indexedContexts) { _, new in new }
            userDefaults.removeObject(forKey: legacyIndexKey)
        }

        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(legacyPrefix) {
            guard let data = userDefaults.data(forKey: key),
                  let context = try? JSONDecoder().decode(ChatRoomStoreContext.self, from: data) else {
                userDefaults.removeObject(forKey: key)
                continue
            }
            contexts[context.storeID] = context
            userDefaults.removeObject(forKey: key)
        }

        if !contexts.isEmpty {
            saveContexts(contexts)
        }
        return contexts
    }

    private func removeContexts(roomID: String) {
        let cleaned = loadContexts().filter { $0.value.roomID != roomID }
        saveContexts(cleaned)
    }

    private func saveContexts(_ contexts: [String: ChatRoomStoreContext]) {
        guard let data = try? JSONEncoder().encode(contexts) else {
            return
        }
        userDefaults.set(data, forKey: indexKey)
    }

    private var indexKey: String {
        "chatRoomStoreContext.index.v3"
    }

    private var legacyIndexKeys: [String] {
        ["chatRoomStoreContext.index.v2"]
    }
}

protocol ChatLocalDataSourceProtocol: Sendable {
    func fetchMessages(scope: ChatRoomScope) async throws -> [ChatMessage]
    func latestServerMessageDate(scope: ChatRoomScope) async throws -> Date?
    func latestMessage(scope: ChatRoomScope) async throws -> ChatMessage?
    func upsert(messages: [ChatMessage], scope: ChatRoomScope) async throws -> [ChatMessage]
    func savePending(message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage]
    func replacePendingMessage(localID: String, with message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage]
    func updateSendStatus(messageID: String, status: ChatSendStatus, scope: ChatRoomScope) async throws -> [ChatMessage]
}

actor CoreDataChatLocalDataSource: ChatLocalDataSourceProtocol {
    private enum Field {
        static let entity = "ChatMessageRecord"
        static let chatID = "chatID"
        static let localTemporaryID = "localTemporaryID"
        static let serverChatID = "serverChatID"
        static let roomID = "roomID"
        static let content = "content"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let senderUserID = "senderUserID"
        static let senderNick = "senderNick"
        static let senderProfileImage = "senderProfileImage"
        static let filesData = "filesData"
        static let sendStatus = "sendStatus"
        static let localCreatedAt = "localCreatedAt"
        static let localCacheKey = "localCacheKey"
    }

    private let persistentContainer: NSPersistentContainer
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(inMemory: Bool = false) {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = Field.entity
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            Self.attribute(Field.chatID, .stringAttributeType, optional: false),
            Self.attribute(Field.localTemporaryID, .stringAttributeType, optional: true),
            Self.attribute(Field.serverChatID, .stringAttributeType, optional: true),
            Self.attribute(Field.roomID, .stringAttributeType, optional: false),
            Self.attribute(Field.content, .stringAttributeType, optional: false),
            Self.attribute(Field.createdAt, .dateAttributeType, optional: true),
            Self.attribute(Field.updatedAt, .dateAttributeType, optional: true),
            Self.attribute(Field.senderUserID, .stringAttributeType, optional: false),
            Self.attribute(Field.senderNick, .stringAttributeType, optional: false),
            Self.attribute(Field.senderProfileImage, .stringAttributeType, optional: true),
            Self.attribute(Field.filesData, .binaryDataAttributeType, optional: false),
            Self.attribute(Field.sendStatus, .stringAttributeType, optional: false),
            Self.attribute(Field.localCreatedAt, .dateAttributeType, optional: false),
            Self.attribute(Field.localCacheKey, .stringAttributeType, optional: true)
        ]
        entity.uniquenessConstraints = [[Field.chatID, Field.localCacheKey]]
        model.entities = [entity]

        persistentContainer = NSPersistentContainer(name: "PikkoChat", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        if inMemory {
            description.type = NSInMemoryStoreType
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            description.url = directory.appendingPathComponent("PikkoChat.sqlite")
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        persistentContainer.persistentStoreDescriptions = [description]

        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        persistentContainer.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError {
            Logger.shared.error("[Chat] CoreData local store failed to load: \(loadError.localizedDescription)")
        }
        persistentContainer.viewContext.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
    }

    func fetchMessages(scope: ChatRoomScope) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        let scopedMessages = try context.fetch(fetchRequest(scope: scope)).compactMap(mapRecord)
        guard scopedMessages.isEmpty, !scope.isStoreInquiry else {
            return deduplicated(scopedMessages)
        }
        return deduplicated(try context.fetch(legacyFetchRequest(roomID: scope.roomID)).compactMap(mapRecord))
    }

    func latestServerMessageDate(scope: ChatRoomScope) async throws -> Date? {
        try await fetchMessages(scope: scope)
            .filter { $0.effectiveServerChatID != nil && $0.sendStatus == .sent }
            .compactMap(\.createdAt)
            .max()
    }

    func latestMessage(scope: ChatRoomScope) async throws -> ChatMessage? {
        let context = persistentContainer.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = scopedPredicate(scope: scope)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.createdAt, ascending: false),
            NSSortDescriptor(key: Field.localCreatedAt, ascending: false)
        ]
        request.fetchLimit = 1

        if let scopedMessage = try context.fetch(request).compactMap(mapRecord).first {
            return scopedMessage
        }

        guard !scope.isStoreInquiry else {
            return nil
        }

        let legacyRequest = legacyFetchRequest(roomID: scope.roomID)
        legacyRequest.sortDescriptors = request.sortDescriptors
        legacyRequest.fetchLimit = 1
        return try context.fetch(legacyRequest).compactMap(mapRecord).first
    }

    @discardableResult
    func upsert(messages: [ChatMessage], scope: ChatRoomScope) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        for message in messages {
            try upsert(message: message, scope: scope, context: context)
        }
        if context.hasChanges {
            try context.save()
        }
        return try await fetchMessages(scope: scope)
    }

    @discardableResult
    func savePending(message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage] {
        try await upsert(messages: [message], scope: scope)
    }

    @discardableResult
    func replacePendingMessage(localID: String, with message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        let serverID = message.effectiveServerChatID
        let pending = try fetchLocalTemporaryRecord(localID: localID, scope: scope, context: context)
            ?? fetchRecord(messageID: localID, scope: scope, context: context)
        let serverRecord = try serverID.flatMap {
            try fetchServerRecord(serverChatID: $0, scope: scope, context: context)
        }

        let record: NSManagedObject
        if let serverRecord {
            record = serverRecord
            if let pending, pending != serverRecord {
                context.delete(pending)
            }
        } else if let pending {
            record = pending
        } else {
            record = NSManagedObject(entity: entityDescription(in: context), insertInto: context)
        }

        let mergedMessage = message.replacingIdentity(
            id: serverID ?? message.id,
            localTemporaryID: localID,
            serverChatID: serverID,
            sendStatus: .sent
        )
        try apply(message: mergedMessage, scope: scope, to: record)
        if context.hasChanges {
            try context.save()
        }
        return try await fetchMessages(scope: scope)
    }

    @discardableResult
    func updateSendStatus(messageID: String, status: ChatSendStatus, scope: ChatRoomScope) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        guard let record = try fetchRecord(messageID: messageID, scope: scope, context: context)
            ?? fetchLocalTemporaryRecord(localID: messageID, scope: scope, context: context) else {
            return []
        }
        record.setValue(status.rawValue, forKey: Field.sendStatus)
        if context.hasChanges {
            try context.save()
        }
        return try await fetchMessages(scope: scope)
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }

    private func fetchRequest(scope: ChatRoomScope) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = scopedPredicate(scope: scope)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.createdAt, ascending: true),
            NSSortDescriptor(key: Field.localCreatedAt, ascending: true)
        ]
        return request
    }

    private func legacyFetchRequest(roomID: String) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == nil",
            Field.roomID,
            roomID,
            Field.localCacheKey
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.createdAt, ascending: true),
            NSSortDescriptor(key: Field.localCreatedAt, ascending: true)
        ]
        return request
    }

    private func scopedPredicate(scope: ChatRoomScope) -> NSPredicate {
        NSPredicate(
            format: "%K == %@ AND %K == %@",
            Field.roomID,
            scope.roomID,
            Field.localCacheKey,
            scope.localCacheKey
        )
    }

    private func fetchRecord(messageID: String, scope: ChatRoomScope, context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Field.chatID,
            messageID,
            Field.localCacheKey,
            scope.localCacheKey
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchLocalTemporaryRecord(localID: String, scope: ChatRoomScope, context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Field.localTemporaryID,
            localID,
            Field.localCacheKey,
            scope.localCacheKey
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchServerRecord(serverChatID: String, scope: ChatRoomScope, context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = NSPredicate(
            format: "(%K == %@ OR %K == %@) AND %K == %@",
            Field.serverChatID,
            serverChatID,
            Field.chatID,
            serverChatID,
            Field.localCacheKey,
            scope.localCacheKey
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func fetchMatchingPendingRecord(for message: ChatMessage, scope: ChatRoomScope, context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@ AND %K == %@ AND %K == %@ AND %K == %@",
            Field.roomID,
            scope.roomID,
            Field.localCacheKey,
            scope.localCacheKey,
            Field.senderUserID,
            message.sender.id,
            Field.content,
            message.content,
            Field.sendStatus,
            ChatSendStatus.sending.rawValue
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.createdAt, ascending: false),
            NSSortDescriptor(key: Field.localCreatedAt, ascending: false)
        ]
        let candidates = try context.fetch(request)
        return candidates.first { record in
            guard let pending = mapRecord(record),
                  pending.effectiveServerChatID == nil,
                  pending.filePaths == message.filePaths else {
                return false
            }
            let pendingDate = pending.createdAt ?? pending.updatedAt
            let serverDate = message.createdAt ?? message.updatedAt
            guard let pendingDate, let serverDate else {
                return true
            }
            return abs(pendingDate.timeIntervalSince(serverDate)) <= 10
        }
    }

    private func upsert(message: ChatMessage, scope: ChatRoomScope, context: NSManagedObjectContext) throws {
        let serverID = message.effectiveServerChatID
        let localID = message.effectiveLocalTemporaryID
        let serverRecord = try serverID.flatMap {
            try fetchServerRecord(serverChatID: $0, scope: scope, context: context)
        }
        let localRecord = try localID.flatMap {
            try fetchLocalTemporaryRecord(localID: $0, scope: scope, context: context)
        } ?? fetchRecord(messageID: message.id, scope: scope, context: context)
        let pendingMatch = try (serverID != nil)
            ? fetchMatchingPendingRecord(for: message, scope: scope, context: context)
            : nil

        let record: NSManagedObject
        if let serverRecord {
            record = serverRecord
            if let localRecord, localRecord != serverRecord {
                context.delete(localRecord)
            }
            if let pendingMatch, pendingMatch != serverRecord {
                context.delete(pendingMatch)
            }
        } else if let localRecord {
            record = localRecord
        } else if let pendingMatch {
            record = pendingMatch
        } else {
            record = NSManagedObject(entity: entityDescription(in: context), insertInto: context)
        }

        let existingLocalID = (record.value(forKey: Field.localTemporaryID) as? String)?.nilIfEmpty
            ?? (record.value(forKey: Field.chatID) as? String).flatMap { $0.hasPrefix("local-") ? $0 : nil }
        let mergedMessage = serverID == nil
            ? message
            : message.replacingIdentity(
                id: serverID,
                localTemporaryID: localID ?? existingLocalID,
                serverChatID: serverID,
                sendStatus: .sent
            )
        try apply(message: mergedMessage, scope: scope, to: record)
    }

    private func entityDescription(in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: Field.entity, in: context)!
    }

    private func apply(message: ChatMessage, scope: ChatRoomScope, to record: NSManagedObject) throws {
        record.setValue(message.id, forKey: Field.chatID)
        record.setValue(message.effectiveLocalTemporaryID, forKey: Field.localTemporaryID)
        record.setValue(message.effectiveServerChatID, forKey: Field.serverChatID)
        record.setValue(message.roomID, forKey: Field.roomID)
        record.setValue(scope.localCacheKey, forKey: Field.localCacheKey)
        record.setValue(message.content, forKey: Field.content)
        record.setValue(message.createdAt, forKey: Field.createdAt)
        record.setValue(message.updatedAt, forKey: Field.updatedAt)
        record.setValue(message.sender.id, forKey: Field.senderUserID)
        record.setValue(message.sender.nick, forKey: Field.senderNick)
        record.setValue(message.sender.profileImagePath, forKey: Field.senderProfileImage)
        record.setValue(try jsonEncoder.encode(message.filePaths), forKey: Field.filesData)
        record.setValue(message.sendStatus.rawValue, forKey: Field.sendStatus)
        if record.value(forKey: Field.localCreatedAt) == nil {
            record.setValue(Date(), forKey: Field.localCreatedAt)
        }
    }

    private func mapRecord(_ record: NSManagedObject) -> ChatMessage? {
        guard let id = record.value(forKey: Field.chatID) as? String,
              let roomID = record.value(forKey: Field.roomID) as? String,
              let content = record.value(forKey: Field.content) as? String,
              let senderUserID = record.value(forKey: Field.senderUserID) as? String,
              let senderNick = record.value(forKey: Field.senderNick) as? String,
              let filesData = record.value(forKey: Field.filesData) as? Data,
              let statusRawValue = record.value(forKey: Field.sendStatus) as? String else {
            return nil
        }
        let files = (try? jsonDecoder.decode([String].self, from: filesData)) ?? []
        return ChatMessage(
            id: id,
            localTemporaryID: (record.value(forKey: Field.localTemporaryID) as? String)?.nilIfEmpty
                ?? (id.hasPrefix("local-") ? id : nil),
            serverChatID: (record.value(forKey: Field.serverChatID) as? String)?.nilIfEmpty
                ?? (id.hasPrefix("local-") ? nil : id),
            roomID: roomID,
            content: content,
            createdAt: record.value(forKey: Field.createdAt) as? Date,
            updatedAt: record.value(forKey: Field.updatedAt) as? Date,
            sender: ChatParticipant(
                id: senderUserID,
                nick: senderNick,
                profileImagePath: record.value(forKey: Field.senderProfileImage) as? String
            ),
            filePaths: files,
            sendStatus: ChatSendStatus(rawValue: statusRawValue) ?? .sent
        )
    }

    private func deduplicated(_ messages: [ChatMessage]) -> [ChatMessage] {
        ChatMessageMergePolicy.deduplicated(messages, currentUserID: nil)
    }
}

@MainActor
protocol ChatRealtimeServiceProtocol: AnyObject {
    func connect(roomID: String, currentUserID: String?, onMessage: @escaping @MainActor (ChatMessage) async -> Void) async throws
    func disconnect()
}

enum ChatFeatureError: Error, Equatable {
    case authenticationRequired
    case networkUnavailable(message: String)
    case unavailable(message: String)
}

extension ChatFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 채팅을 이용할 수 있어요."
        case .networkUnavailable(let message):
            return message
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
protocol ChatInteracting {
    var currentUserID: String? { get }
    var target: ChatTarget? { get }

    func loadInitialRoomList() async throws -> [ChatRoom]
    func loadLocalConversationSummaries() async throws -> [ChatLocalConversationSummary]
    func createOrFetchStoreChatRoom() async throws -> ChatRoom
    func createOrFetchUserChatRoom() async throws -> ChatRoom
    func loadCachedMessages(scope: ChatRoomScope) async throws -> [ChatMessage]
    func synchronizeMessages(scope: ChatRoomScope) async throws -> [ChatMessage]
    func startRealtime(scope: ChatRoomScope, onMessage: @escaping @MainActor (ChatMessage) async -> Void) async throws
    func stopRealtime()
    func makePendingMessage(roomID: String, content: String, files: [String]) throws -> ChatMessage
    func savePendingMessage(_ message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage]
    func replacePendingMessage(localID: String, with message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage]
    func markMessageFailed(messageID: String, scope: ChatRoomScope) async throws -> [ChatMessage]
    func loadMessages(roomID: String, after next: String?) async throws -> [ChatMessage]
    func sendMessage(scope: ChatRoomScope, content: String, files: [String]) async throws -> ChatMessage
    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> [String]
    func makeContext(for room: ChatRoom, entryPoint: ChatRoomEntryPoint) -> ChatRoomContext
    func makeContext(for summary: ChatLocalConversationSummary) -> ChatRoomContext
    func cachedStoreContext(roomID: String) -> ChatRoomStoreContext?
}

@MainActor
struct ChatInteractor: ChatInteracting {
    let currentUserID: String?
    let target: ChatTarget?

    private let chatRepository: ChatRepository
    private let localDataSource: any ChatLocalDataSourceProtocol
    private let realtimeService: any ChatRealtimeServiceProtocol
    private let storeRepository: StoreRepository
    private let sessionStore: SessionStore
    private let storeContextCache: any ChatRoomStoreContextCaching

    init(
        target: ChatTarget? = nil,
        chatRepository: ChatRepository,
        localDataSource: any ChatLocalDataSourceProtocol,
        realtimeService: any ChatRealtimeServiceProtocol,
        storeRepository: StoreRepository,
        sessionStore: SessionStore,
        storeContextCache: any ChatRoomStoreContextCaching = UserDefaultsChatRoomStoreContextCache.shared
    ) {
        self.target = target
        self.chatRepository = chatRepository
        self.localDataSource = localDataSource
        self.realtimeService = realtimeService
        self.storeRepository = storeRepository
        self.sessionStore = sessionStore
        self.storeContextCache = storeContextCache
        self.currentUserID = sessionStore.currentUserID
    }

    func loadInitialRoomList() async throws -> [ChatRoom] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        do {
            let remoteRooms = try await chatRepository.fetchChatRooms()
            var roomsWithLocalLastMessage: [ChatRoom] = []
            for room in remoteRooms {
                guard room.lastMessage == nil else {
                    roomsWithLocalLastMessage.append(room)
                    continue
                }
                let context = makeContext(for: room, entryPoint: .chatList)
                if context.hasRoomIDCollision {
                    Logger.shared.info(
                        "[ChatRoomContext] room list skips ambiguous local last message roomId=\(room.id) mappedStoreIds=\(context.collidingStoreIDs.joined(separator: ","))"
                    )
                    roomsWithLocalLastMessage.append(room)
                    continue
                }
                if let localLastMessage = try? await localDataSource.latestMessage(scope: context.localCacheScope) {
                    roomsWithLocalLastMessage.append(room.updating(lastMessage: localLastMessage))
                } else {
                    roomsWithLocalLastMessage.append(room)
                }
            }
            return roomsWithLocalLastMessage
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func loadLocalConversationSummaries() async throws -> [ChatLocalConversationSummary] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        var summaries: [ChatLocalConversationSummary] = []
        for context in storeContextCache.allContexts() {
            let scope = ChatRoomScope(
                roomID: context.roomID,
                storeID: context.storeID,
                opponentID: context.opponentID
            )
            let latestMessage = try? await localDataSource.latestMessage(scope: scope)
            let updatedAt = latestMessage?.createdAt ?? latestMessage?.updatedAt ?? context.updatedAt
            summaries.append(
                ChatLocalConversationSummary(
                    id: scope.localCacheKey,
                    serverRoomID: context.roomID,
                    localCacheKey: scope.localCacheKey,
                    storeID: context.storeID,
                    storeName: context.storeName,
                    opponentID: context.opponentID,
                    lastLocalMessage: latestMessage,
                    updatedAt: updatedAt
                )
            )
        }

        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func createOrFetchStoreChatRoom() async throws -> ChatRoom {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }
        guard case let .store(storeID, storeName, ownerID, _, _) = target else {
            throw ChatFeatureError.unavailable(message: "문의할 가게 정보를 찾지 못했어요.")
        }
        let normalizedStoreID = storeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStoreID.isEmpty else {
            throw ChatFeatureError.unavailable(message: "문의할 가게 정보를 찾지 못했어요.")
        }

        do {
            let resolvedOwnerID: String?
            if let ownerID = ownerID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ownerID.isEmpty {
                resolvedOwnerID = ownerID
            } else {
                let store = try await storeRepository.fetchStoreDetail(storeID: storeID)
                resolvedOwnerID = store.owner?.id
            }

            guard let ownerID = resolvedOwnerID, !ownerID.isEmpty else {
                throw ChatFeatureError.unavailable(message: "가게 문의 대상을 찾지 못했어요.")
            }
            if ownerID == sessionStore.currentUserID {
                throw ChatFeatureError.unavailable(message: "내 가게에는 채팅 문의를 보낼 수 없어요.")
            }

            let previousContextForStore = storeContextCache.context(forStoreID: normalizedStoreID)
            let creationMode = ChatRoomCreationMode.storeInquiry(
                storeID: normalizedStoreID,
                opponentID: ownerID,
                storeName: storeName
            )
            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom sendsStoreIdInRequest=\(ChatRoomContextPolicy.sendsStoreIDInCreateRoomRequest) \(creationMode.debugDescription)"
            )
            let room = try await chatRepository.createOrFetchChatRoom(mode: creationMode)
            let normalizedStoreName = storeName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let context = ChatRoomStoreContext(
                roomID: room.id,
                storeID: normalizedStoreID,
                storeName: normalizedStoreName ?? storeName,
                opponentID: ownerID,
                updatedAt: Date()
            )
            let didSaveContext = storeContextCache.save(context)
            if let previousContextForStore,
               previousContextForStore.roomID != room.id {
                Logger.shared.warning(
                    "[ChatRoomContext] store roomId changed storeId=\(normalizedStoreID) oldRoomId=\(previousContextForStore.roomID) newRoomId=\(room.id)"
                )
            }
            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom resultRoomId=\(room.id) \(creationMode.debugDescription) cachedStoreContext=\(didSaveContext) cachedTitle=\(didSaveContext ? context.storeName : "-")"
            )
            guard didSaveContext else {
                return room
            }
            return room.applyingStoreContext(storeID: normalizedStoreID, storeName: context.storeName)
        } catch let error as ChatFeatureError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func createOrFetchUserChatRoom() async throws -> ChatRoom {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }
        guard case let .user(opponentID, _, _) = target,
              !opponentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatFeatureError.unavailable(message: "채팅 상대를 찾지 못했어요.")
        }
        if opponentID == sessionStore.currentUserID {
            throw ChatFeatureError.unavailable(message: "내 계정에는 채팅을 시작할 수 없어요.")
        }

        do {
            let creationMode = ChatRoomCreationMode.user(opponentID: opponentID)
            Logger.shared.debug("[ChatRepository] createOrFetchRoom \(creationMode.debugDescription)")
            let room = try await chatRepository.createOrFetchChatRoom(mode: creationMode)
            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom resultRoomId=\(room.id) \(creationMode.debugDescription)"
            )
            return room
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func loadCachedMessages(scope: ChatRoomScope) async throws -> [ChatMessage] {
        Logger.shared.debug(
            "[ChatViewModel] loadLocalMessages scope=\(scope.localCacheKey)"
        )
        return try await localDataSource.fetchMessages(scope: scope)
    }

    func synchronizeMessages(scope: ChatRoomScope) async throws -> [ChatMessage] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        do {
            let mappedStoreIDs = storeContextCache.contexts(for: scope.roomID).map(\.storeID)
            if scope.isStoreInquiry, mappedStoreIDs.count > 1 {
                Logger.shared.info(
                    "[ChatRoomContext] storeScopedServerHistoryMergeSkipped roomId=\(scope.roomID) currentStoreId=\(scope.storeID ?? "-") storeCount=\(mappedStoreIDs.count) storeIds=\(mappedStoreIDs.joined(separator: ","))"
                )
                return try await localDataSource.fetchMessages(scope: scope)
            }

            let next = try await localDataSource.latestServerMessageDate(scope: scope)
                .map(Self.utcQueryString)
            Logger.shared.debug("[ChatViewModel] syncLatestMessages since=\(next ?? "nil") scope=\(scope.localCacheKey)")
            let messages = try await chatRepository.fetchMessages(roomID: scope.roomID, next: next)
            guard !messages.isEmpty else {
                return try await localDataSource.fetchMessages(scope: scope)
            }
            let existingMessages = (try? await localDataSource.fetchMessages(scope: scope)) ?? []
            for message in messages {
                if let serverID = message.effectiveServerChatID,
                   existingMessages.contains(where: { $0.effectiveServerChatID == serverID }) {
#if DEBUG
                    if ChatDebugOptions.isMergeLoggingEnabled {
                        DebugLogDeduplicator.shared.printOnce(
                            key: "ChatMerge.skipDuplicate.\(serverID).sync",
                            message: "[ChatMerge] skipDuplicate serverChatId=\(serverID) source=sync"
                        )
                    }
#endif
                } else if let serverID = message.effectiveServerChatID,
                          let pending = existingMessages.first(where: {
                              ChatMessageMergePolicy.deduplicated([$0, message], currentUserID: sessionStore.currentUserID).count == 1
                                  && $0.effectiveServerChatID == nil
                                  && $0.sendStatus == .sending
                          }) {
                    let localID = pending.effectiveLocalTemporaryID ?? pending.id
#if DEBUG
                    if ChatDebugOptions.isMergeLoggingEnabled {
                        DebugLogDeduplicator.shared.printOnce(
                            key: "ChatMerge.replaceOptimistic.\(localID).\(serverID).sync",
                            message: "[ChatMerge] replaceOptimistic localTemporaryId=\(localID) serverChatId=\(serverID) source=sync"
                        )
                    }
#endif
                }
            }
            return try await localDataSource.upsert(messages: messages, scope: scope)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func startRealtime(scope: ChatRoomScope, onMessage: @escaping @MainActor (ChatMessage) async -> Void) async throws {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        let mappedStoreIDs = storeContextCache.contexts(for: scope.roomID).map(\.storeID)
        Logger.shared.debug(
            "[ChatSocket] connect context roomId=\(scope.roomID) storeId=\(scope.storeID ?? "-") opponentId=\(scope.opponentID ?? "-") localCacheKey=\(scope.localCacheKey) namespace=/chats-\(scope.roomID)"
        )
        if scope.isStoreInquiry, mappedStoreIDs.count > 1 {
            Logger.shared.debug(
                "[ChatSocket] namespace remains roomId-scoped despite store collision roomId=\(scope.roomID) currentStoreId=\(scope.storeID ?? "-") mappedStoreIds=\(mappedStoreIDs.joined(separator: ","))"
            )
        }
        try await realtimeService.connect(roomID: scope.roomID, currentUserID: sessionStore.currentUserID) { [localDataSource] message in
            do {
                let existingMessages = (try? await localDataSource.fetchMessages(scope: scope)) ?? []
                if let serverID = message.effectiveServerChatID,
                   existingMessages.contains(where: { $0.effectiveServerChatID == serverID }) {
#if DEBUG
                    if ChatDebugOptions.isMergeLoggingEnabled {
                        DebugLogDeduplicator.shared.printOnce(
                            key: "ChatMerge.skipDuplicate.\(serverID).socket",
                            message: "[ChatMerge] skipDuplicate serverChatId=\(serverID) source=socket"
                        )
                    }
#endif
                } else if let serverID = message.effectiveServerChatID,
                          let pending = existingMessages.first(where: {
                              ChatMessageMergePolicy.deduplicated([$0, message], currentUserID: sessionStore.currentUserID).count == 1
                                  && $0.effectiveServerChatID == nil
                                  && $0.sendStatus == .sending
                          }) {
                    let localID = pending.effectiveLocalTemporaryID ?? pending.id
#if DEBUG
                    if ChatDebugOptions.isMergeLoggingEnabled {
                        DebugLogDeduplicator.shared.printOnce(
                            key: "ChatMerge.replaceOptimistic.\(localID).\(serverID).socket",
                            message: "[ChatMerge] replaceOptimistic localTemporaryId=\(localID) serverChatId=\(serverID) source=socket"
                        )
                    }
#endif
                }
                let messages = try await localDataSource.upsert(messages: [message], scope: scope)
                touchStoreConversation(scope: scope, latestActivityDate: message.createdAt ?? message.updatedAt ?? Date())
                if let stored = messages.first(where: { $0.id == message.id }) {
                    await onMessage(stored)
                } else {
                    await onMessage(message)
                }
            } catch {
                Logger.shared.warning("[Chat] socket message local upsert failed: \(error.localizedDescription)")
                await onMessage(message)
            }
            NotificationCenter.default.postChatRoomDidUpdate(message: message)
        }
    }

    func stopRealtime() {
        realtimeService.disconnect()
    }

    func makePendingMessage(roomID: String, content: String, files: [String]) throws -> ChatMessage {
        guard let currentUserID = sessionStore.currentUserID else {
            throw ChatFeatureError.authenticationRequired
        }

        let localID = "local-\(UUID().uuidString)"
        return ChatMessage(
            id: localID,
            localTemporaryID: localID,
            roomID: roomID,
            content: content,
            createdAt: Date(),
            updatedAt: nil,
            sender: ChatParticipant(
                id: currentUserID,
                nick: sessionStore.nick ?? "나",
                profileImagePath: sessionStore.profileImagePath
            ),
            filePaths: files,
            sendStatus: .sending
        )
    }

    func savePendingMessage(_ message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage] {
        let messages = try await localDataSource.savePending(message: message, scope: scope)
        touchStoreConversation(scope: scope, latestActivityDate: message.createdAt ?? Date())
        return messages
    }

    func replacePendingMessage(localID: String, with message: ChatMessage, scope: ChatRoomScope) async throws -> [ChatMessage] {
        let messages = try await localDataSource.replacePendingMessage(localID: localID, with: message, scope: scope)
        touchStoreConversation(scope: scope, latestActivityDate: message.createdAt ?? message.updatedAt ?? Date())
        return messages
    }

    func markMessageFailed(messageID: String, scope: ChatRoomScope) async throws -> [ChatMessage] {
        let messages = try await localDataSource.updateSendStatus(messageID: messageID, status: .failed, scope: scope)
        touchStoreConversation(scope: scope, latestActivityDate: Date())
        return messages
    }

    func loadMessages(roomID: String, after next: String? = nil) async throws -> [ChatMessage] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        do {
            return try await chatRepository.fetchMessages(roomID: roomID, next: next)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func sendMessage(scope: ChatRoomScope, content: String, files: [String]) async throws -> ChatMessage {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !files.isEmpty else {
            throw ChatFeatureError.unavailable(message: "메시지나 파일을 추가해 주세요.")
        }

        do {
            let sentMessage = try await chatRepository.sendMessage(roomID: scope.roomID, content: trimmed, files: files)
            touchStoreConversation(scope: scope, latestActivityDate: sentMessage.createdAt ?? sentMessage.updatedAt ?? Date())
            NotificationCenter.default.postChatRoomDidUpdate(message: sentMessage)
            return sentMessage
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> [String] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }
        guard !files.isEmpty else { return [] }

        do {
            return try await chatRepository.uploadFiles(roomID: roomID, files: files)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> ChatFeatureError {
        if let chatError = error as? ChatFeatureError {
            return chatError
        }

        guard let networkError = error as? NetworkError else {
            return .unavailable(message: error.localizedDescription)
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        if networkError.isConfigurationFailure {
            return .unavailable(message: networkError.appConfigurationError?.userMessage ?? "앱 설정을 확인해 주세요.")
        }

        switch networkError {
        case .invalidRequest, .abnormalRequest:
            return .unavailable(message: "채팅 요청 형식이 올바르지 않아요.")
        case .forbidden, .businessAuthorization:
            return .unavailable(message: "채팅방 참여자가 아닙니다.")
        case .notFound(let message),
             .conflict(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "데이터를 불러오지 못했어요.")
        case .transport:
            Logger.shared.warning("[Chat] network failed error=transport")
            return .networkUnavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }

    private static func utcQueryString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    func makeContext(for room: ChatRoom, entryPoint: ChatRoomEntryPoint) -> ChatRoomContext {
        let opponent = room.participants.first { $0.id != sessionStore.currentUserID } ?? room.participants.first
        let explicitStoreID: String?
        let explicitStoreName: String?
        if case let .store(storeID, storeName, _, _, _) = target {
            explicitStoreID = storeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            explicitStoreName = storeName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } else {
            explicitStoreID = nil
            explicitStoreName = nil
        }
        let cachedContext: ChatRoomStoreContext?
        switch entryPoint {
        case .storeDetail:
            cachedContext = explicitStoreID.flatMap { storeContextCache.context(forStoreID: $0) }
                ?? storeContextCache.context(for: room.id)
        case .storeScopedChatList:
            cachedContext = storeContextCache.context(for: room.id)
        case .chatList, .userProfile:
            cachedContext = nil
        }
        let serverStoreID = room.storeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let serverStoreName = room.storeName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let cachedStoreID: String?
        let cachedStoreName: String?
        if let cachedContext,
           let serverStoreID,
           serverStoreID != cachedContext.storeID {
            Logger.shared.warning(
                "[ChatRoomContext] ignoring cached store context roomId=\(room.id) cachedStoreId=\(cachedContext.storeID) serverStoreId=\(serverStoreID)"
            )
            cachedStoreID = nil
            cachedStoreName = nil
        } else {
            cachedStoreID = cachedContext?.storeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            cachedStoreName = cachedContext?.storeName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        let explicitContextIsValid: Bool
        if let explicitStoreID {
            explicitContextIsValid =
                storeContextCache.context(forStoreID: explicitStoreID)?.roomID == room.id
                || serverStoreID == explicitStoreID
                || serverStoreID == nil
        } else {
            explicitContextIsValid = false
        }

        if let explicitStoreID,
           let cachedStoreID,
           explicitStoreID != cachedStoreID {
#if DEBUG
            DebugLogDeduplicator.shared.printOnce(
                key: "ChatRoomContext.multipleStoreScopesShareServerRoom.\(room.id).\(cachedStoreID).\(explicitStoreID)",
                level: .info,
                message: "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(room.id) oldStoreId=\(cachedStoreID) newStoreId=\(explicitStoreID)"
            )
#else
            Logger.shared.info(
                "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(room.id) oldStoreId=\(cachedStoreID) newStoreId=\(explicitStoreID)"
            )
#endif
        }

        let resolvedStoreID = explicitContextIsValid ? explicitStoreID : (cachedStoreID ?? serverStoreID)
        let resolvedStoreName = explicitContextIsValid ? (explicitStoreName ?? cachedStoreName ?? serverStoreName) : (cachedStoreName ?? serverStoreName)
        let collidingStoreIDs = storeContextCache.contexts(for: room.id).map(\.storeID)
        let hasRoomIDCollision = collidingStoreIDs.count > 1
        if hasRoomIDCollision {
#if DEBUG
            DebugLogDeduplicator.shared.printOnce(
                key: "ChatRoomContext.multipleStoreScopesShareServerRoom.\(room.id).\(collidingStoreIDs.joined(separator: ","))",
                level: .info,
                message: "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(room.id) currentStoreId=\(explicitStoreID ?? resolvedStoreID ?? "-") storeCount=\(collidingStoreIDs.count) storeIds=\(collidingStoreIDs.joined(separator: ","))"
            )
#else
            Logger.shared.info(
                "[ChatRoomContext] multipleStoreScopesShareServerRoom roomId=\(room.id) currentStoreId=\(explicitStoreID ?? resolvedStoreID ?? "-") storeCount=\(collidingStoreIDs.count) storeIds=\(collidingStoreIDs.joined(separator: ","))"
            )
#endif
        }

        let resolvedOpponentID = cachedContext?.opponentID.nilIfEmpty
            ?? room.opponentID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? opponent?.id
        let resolvedOpponentName = room.opponentName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? opponent?.nick.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let displayTitle = resolvedStoreName
            ?? resolvedOpponentName
            ?? "채팅"

        return ChatRoomContext(
            entryPoint: entryPoint,
            roomID: room.id,
            opponentID: resolvedOpponentID,
            storeID: resolvedStoreID,
            storeName: resolvedStoreName,
            displayTitle: displayTitle,
            canUseStoreScopedTitle: resolvedStoreID != nil && resolvedStoreName != nil,
            hasRoomIDCollision: hasRoomIDCollision,
            collidingStoreIDs: collidingStoreIDs
        )
    }

    func makeContext(for summary: ChatLocalConversationSummary) -> ChatRoomContext {
        ChatRoomContext(
            entryPoint: .storeScopedChatList,
            roomID: summary.serverRoomID,
            opponentID: summary.opponentID,
            storeID: summary.storeID,
            storeName: summary.storeName,
            displayTitle: summary.storeName,
            canUseStoreScopedTitle: true,
            hasRoomIDCollision: storeContextCache.contexts(for: summary.serverRoomID).count > 1,
            collidingStoreIDs: storeContextCache.contexts(for: summary.serverRoomID).map(\.storeID)
        )
    }

    func cachedStoreContext(roomID: String) -> ChatRoomStoreContext? {
        storeContextCache.context(for: roomID)
    }

}

private extension ChatInteractor {
    func touchStoreConversation(scope: ChatRoomScope, latestActivityDate: Date) {
        guard let storeID = scope.storeID?.nilIfEmpty,
              let opponentID = scope.opponentID?.nilIfEmpty,
              let existingContext = storeContextCache.context(forStoreID: storeID) else {
            if scope.isStoreInquiry {
                Logger.shared.warning(
                    "[ChatRoomContext] store-scoped activity could not update summary roomId=\(scope.roomID) storeId=\(scope.storeID ?? "-") opponentId=\(scope.opponentID ?? "-")"
                )
            }
            return
        }

        let context = ChatRoomStoreContext(
            roomID: scope.roomID,
            storeID: storeID,
            storeName: existingContext.storeName,
            opponentID: opponentID,
            updatedAt: latestActivityDate
        )
        _ = storeContextCache.save(context)
    }
}

enum ChatRoomUpdateNotificationKey {
    static let roomID = "roomID"
    static let message = "message"
}

extension Notification.Name {
    static let pikkoChatRoomDidUpdate = Notification.Name("pikkoChatRoomDidUpdate")
}

extension NotificationCenter {
    func postChatRoomDidUpdate(message: ChatMessage) {
        post(
            name: .pikkoChatRoomDidUpdate,
            object: nil,
            userInfo: [
                ChatRoomUpdateNotificationKey.roomID: message.roomID,
                ChatRoomUpdateNotificationKey.message: message
            ]
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
