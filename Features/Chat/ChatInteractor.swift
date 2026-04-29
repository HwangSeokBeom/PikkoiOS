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
    let roomID: String
    let content: String
    let createdAt: Date?
    let updatedAt: Date?
    let sender: ChatParticipant
    let filePaths: [String]
    let sendStatus: ChatSendStatus

    init(
        id: String,
        roomID: String,
        content: String,
        createdAt: Date?,
        updatedAt: Date?,
        sender: ChatParticipant,
        filePaths: [String],
        sendStatus: ChatSendStatus = .sent
    ) {
        self.id = id
        self.roomID = roomID
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sender = sender
        self.filePaths = filePaths
        self.sendStatus = sendStatus
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

    func updating(lastMessage: ChatMessage) -> ChatRoom {
        ChatRoom(
            id: id,
            createdAt: createdAt,
            updatedAt: lastMessage.createdAt ?? updatedAt,
            participants: participants,
            lastMessage: lastMessage
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
}

enum ChatRoomContextPolicy {
    static let supportsStoreScopedRooms = true
}

struct CreateChatRoomRequestDTO: Encodable, Sendable {
    let opponentID: String?
    let storeID: String?

    private enum CodingKeys: String, CodingKey {
        case opponentID = "opponent_id"
        case storeID = "store_id"
    }

    init(opponentID: String) {
        self.opponentID = opponentID
        self.storeID = nil
    }

    init(storeID: String) {
        self.opponentID = nil
        self.storeID = storeID
    }
}

enum ChatRoomCreationMode: Equatable, Sendable {
    case storeID(String)
    case opponentID(String)

    var requestBodyKey: String {
        switch self {
        case .storeID:
            return "store_id"
        case .opponentID:
            return "opponent_id"
        }
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

    private enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case createdAt
        case updatedAt
        case participants
        case lastChat
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
        let requestDTO: CreateChatRoomRequestDTO
        switch mode {
        case .storeID(let storeID):
            requestDTO = CreateChatRoomRequestDTO(storeID: storeID)
        case .opponentID(let opponentID):
            requestDTO = CreateChatRoomRequestDTO(opponentID: opponentID)
        }
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                requestDTO
            )
        )
        let endpoint = Endpoint<ChatRoomDTO>(
            path: "/v1/chats",
            method: .post,
            body: body,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
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
        ChatRoom(
            id: dto.roomID,
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601),
            participants: dto.participants.map(mapParticipant),
            lastMessage: dto.lastChat.map(mapMessage)
        )
    }

    func mapMessage(_ dto: ChatMessageDTO) -> ChatMessage {
        ChatMessage(
            id: dto.chatID,
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

protocol ChatLocalDataSourceProtocol: Sendable {
    func fetchMessages(roomID: String) async throws -> [ChatMessage]
    func latestServerMessageDate(roomID: String) async throws -> Date?
    func latestMessagesByRoomID() async throws -> [String: ChatMessage]
    func upsert(messages: [ChatMessage]) async throws -> [ChatMessage]
    func savePending(message: ChatMessage) async throws -> [ChatMessage]
    func replacePendingMessage(localID: String, with message: ChatMessage) async throws -> [ChatMessage]
    func updateSendStatus(messageID: String, status: ChatSendStatus) async throws -> [ChatMessage]
}

actor CoreDataChatLocalDataSource: ChatLocalDataSourceProtocol {
    private enum Field {
        static let entity = "ChatMessageRecord"
        static let chatID = "chatID"
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
            Self.attribute(Field.roomID, .stringAttributeType, optional: false),
            Self.attribute(Field.content, .stringAttributeType, optional: false),
            Self.attribute(Field.createdAt, .dateAttributeType, optional: true),
            Self.attribute(Field.updatedAt, .dateAttributeType, optional: true),
            Self.attribute(Field.senderUserID, .stringAttributeType, optional: false),
            Self.attribute(Field.senderNick, .stringAttributeType, optional: false),
            Self.attribute(Field.senderProfileImage, .stringAttributeType, optional: true),
            Self.attribute(Field.filesData, .binaryDataAttributeType, optional: false),
            Self.attribute(Field.sendStatus, .stringAttributeType, optional: false),
            Self.attribute(Field.localCreatedAt, .dateAttributeType, optional: false)
        ]
        entity.uniquenessConstraints = [[Field.chatID]]
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

    func fetchMessages(roomID: String) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        let request = fetchRequest(roomID: roomID)
        return try context.fetch(request).compactMap(mapRecord)
    }

    func latestServerMessageDate(roomID: String) async throws -> Date? {
        try await fetchMessages(roomID: roomID)
            .filter { !$0.id.hasPrefix("local-") && $0.sendStatus == .sent }
            .compactMap(\.createdAt)
            .max()
    }

    func latestMessagesByRoomID() async throws -> [String: ChatMessage] {
        let context = persistentContainer.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.createdAt, ascending: false),
            NSSortDescriptor(key: Field.localCreatedAt, ascending: false)
        ]

        var result: [String: ChatMessage] = [:]
        for record in try context.fetch(request) {
            guard let message = mapRecord(record), result[message.roomID] == nil else {
                continue
            }
            result[message.roomID] = message
        }
        return result
    }

    @discardableResult
    func upsert(messages: [ChatMessage]) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        for message in messages {
            let record = try fetchRecord(messageID: message.id, context: context) ?? NSManagedObject(
                entity: entityDescription(in: context),
                insertInto: context
            )
            try apply(message: message, to: record)
        }
        if context.hasChanges {
            try context.save()
        }
        return try await fetchMessages(roomID: messages.first?.roomID ?? "")
    }

    @discardableResult
    func savePending(message: ChatMessage) async throws -> [ChatMessage] {
        try await upsert(messages: [message])
    }

    @discardableResult
    func replacePendingMessage(localID: String, with message: ChatMessage) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        if let pending = try fetchRecord(messageID: localID, context: context) {
            context.delete(pending)
        }
        let record = try fetchRecord(messageID: message.id, context: context) ?? NSManagedObject(
            entity: entityDescription(in: context),
            insertInto: context
        )
        try apply(message: message, to: record)
        if context.hasChanges {
            try context.save()
        }
        return try await fetchMessages(roomID: message.roomID)
    }

    @discardableResult
    func updateSendStatus(messageID: String, status: ChatSendStatus) async throws -> [ChatMessage] {
        let context = persistentContainer.viewContext
        guard let record = try fetchRecord(messageID: messageID, context: context),
              let roomID = record.value(forKey: Field.roomID) as? String else {
            return []
        }
        record.setValue(status.rawValue, forKey: Field.sendStatus)
        if context.hasChanges {
            try context.save()
        }
        return try await fetchMessages(roomID: roomID)
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

    private func fetchRequest(roomID: String) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = NSPredicate(format: "%K == %@", Field.roomID, roomID)
        request.sortDescriptors = [
            NSSortDescriptor(key: Field.createdAt, ascending: true),
            NSSortDescriptor(key: Field.localCreatedAt, ascending: true)
        ]
        return request
    }

    private func fetchRecord(messageID: String, context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: Field.entity)
        request.predicate = NSPredicate(format: "%K == %@", Field.chatID, messageID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func entityDescription(in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: Field.entity, in: context)!
    }

    private func apply(message: ChatMessage, to record: NSManagedObject) throws {
        record.setValue(message.id, forKey: Field.chatID)
        record.setValue(message.roomID, forKey: Field.roomID)
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
}

@MainActor
protocol ChatRealtimeServiceProtocol: AnyObject {
    func connect(roomID: String, onMessage: @escaping @MainActor (ChatMessage) async -> Void) async throws
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
    func createOrFetchStoreChatRoom() async throws -> ChatRoom
    func createOrFetchUserChatRoom() async throws -> ChatRoom
    func loadCachedMessages(roomID: String) async throws -> [ChatMessage]
    func synchronizeMessages(roomID: String) async throws -> [ChatMessage]
    func startRealtime(roomID: String, onMessage: @escaping @MainActor (ChatMessage) async -> Void) async throws
    func stopRealtime()
    func makePendingMessage(roomID: String, content: String, files: [String]) throws -> ChatMessage
    func savePendingMessage(_ message: ChatMessage) async throws -> [ChatMessage]
    func replacePendingMessage(localID: String, with message: ChatMessage) async throws -> [ChatMessage]
    func markMessageFailed(messageID: String) async throws -> [ChatMessage]
    func loadMessages(roomID: String, after next: String?) async throws -> [ChatMessage]
    func sendMessage(roomID: String, content: String, files: [String]) async throws -> ChatMessage
    func uploadFiles(roomID: String, files: [ChatUploadFile]) async throws -> [String]
    func makeContext(for room: ChatRoom, entryPoint: ChatRoomEntryPoint) -> ChatRoomContext
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

    init(
        target: ChatTarget? = nil,
        chatRepository: ChatRepository,
        localDataSource: any ChatLocalDataSourceProtocol,
        realtimeService: any ChatRealtimeServiceProtocol,
        storeRepository: StoreRepository,
        sessionStore: SessionStore
    ) {
        self.target = target
        self.chatRepository = chatRepository
        self.localDataSource = localDataSource
        self.realtimeService = realtimeService
        self.storeRepository = storeRepository
        self.sessionStore = sessionStore
        self.currentUserID = sessionStore.currentUserID
    }

    func loadInitialRoomList() async throws -> [ChatRoom] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        do {
            let remoteRooms = try await chatRepository.fetchChatRooms()
            let latestLocalMessages = (try? await localDataSource.latestMessagesByRoomID()) ?? [:]
            return remoteRooms.map { room in
                guard room.lastMessage == nil,
                      let localLastMessage = latestLocalMessages[room.id] else {
                    return room
                }
                return room.updating(lastMessage: localLastMessage)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
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

            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom storeIdExists=true opponentIdExists=true selectedRoomCreationMode=store_id requestBodyKey=store_id storeId=\(normalizedStoreID) opponentId=\(ownerID) storeName=\(storeName)"
            )

            do {
                let room = try await chatRepository.createOrFetchChatRoom(mode: .storeID(normalizedStoreID))
                Logger.shared.debug(
                    "[ChatRepository] createOrFetchRoom resultRoomId=\(room.id) selectedRoomCreationMode=store_id requestBodyKey=store_id storeId=\(normalizedStoreID) opponentId=\(ownerID)"
                )
                return room
            } catch let error as NetworkError where error.allowsStoreChatFallbackToOpponent {
                Logger.shared.warning(
                    "[ChatRepository] createOrFetchRoom store_id failed; falling back to opponent_id storeId=\(normalizedStoreID) opponentId=\(ownerID) error=\(error.localizedDescription)"
                )
            }

            let room = try await chatRepository.createOrFetchChatRoom(mode: .opponentID(ownerID))
            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom resultRoomId=\(room.id) selectedRoomCreationMode=opponent_id requestBodyKey=opponent_id storeId=\(normalizedStoreID) opponentId=\(ownerID)"
            )
            return room
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
            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom storeIdExists=false opponentIdExists=true selectedRoomCreationMode=opponent_id requestBodyKey=opponent_id opponentId=\(opponentID)"
            )
            let room = try await chatRepository.createOrFetchChatRoom(mode: .opponentID(opponentID))
            Logger.shared.debug(
                "[ChatRepository] createOrFetchRoom resultRoomId=\(room.id) selectedRoomCreationMode=opponent_id requestBodyKey=opponent_id opponentId=\(opponentID)"
            )
            return room
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func loadCachedMessages(roomID: String) async throws -> [ChatMessage] {
        try await localDataSource.fetchMessages(roomID: roomID)
    }

    func synchronizeMessages(roomID: String) async throws -> [ChatMessage] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        do {
            let next = try await localDataSource.latestServerMessageDate(roomID: roomID)
                .map(Self.utcQueryString)
            Logger.shared.debug("[ChatViewModel] syncLatestMessages since=\(next ?? "nil")")
            let messages = try await chatRepository.fetchMessages(roomID: roomID, next: next)
            guard !messages.isEmpty else {
                return try await localDataSource.fetchMessages(roomID: roomID)
            }
            return try await localDataSource.upsert(messages: messages)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func startRealtime(roomID: String, onMessage: @escaping @MainActor (ChatMessage) async -> Void) async throws {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        try await realtimeService.connect(roomID: roomID) { [localDataSource] message in
            do {
                let messages = try await localDataSource.upsert(messages: [message])
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

        return ChatMessage(
            id: "local-\(UUID().uuidString)",
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

    func savePendingMessage(_ message: ChatMessage) async throws -> [ChatMessage] {
        try await localDataSource.savePending(message: message)
    }

    func replacePendingMessage(localID: String, with message: ChatMessage) async throws -> [ChatMessage] {
        try await localDataSource.replacePendingMessage(localID: localID, with: message)
    }

    func markMessageFailed(messageID: String) async throws -> [ChatMessage] {
        try await localDataSource.updateSendStatus(messageID: messageID, status: .failed)
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

    func sendMessage(roomID: String, content: String, files: [String]) async throws -> ChatMessage {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !files.isEmpty else {
            throw ChatFeatureError.unavailable(message: "메시지나 파일을 추가해 주세요.")
        }

        do {
            let sentMessage = try await chatRepository.sendMessage(roomID: roomID, content: trimmed, files: files)
            _ = try await localDataSource.upsert(messages: [sentMessage])
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
        let targetStoreID: String?
        let targetStoreName: String?
        if case let .store(storeID, storeName, _, _, _) = target {
            targetStoreID = storeID
            targetStoreName = storeName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } else {
            targetStoreID = nil
            targetStoreName = nil
        }
        let displayTitle = targetStoreName
            ?? opponent?.nick.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? target?.preferredTitle
            ?? "채팅"

        return ChatRoomContext(
            entryPoint: entryPoint,
            roomID: room.id,
            opponentID: opponent?.id,
            storeID: targetStoreID,
            storeName: targetStoreName,
            displayTitle: displayTitle,
            canUseStoreScopedTitle: targetStoreID != nil && ChatRoomContextPolicy.supportsStoreScopedRooms
        )
    }
}

private extension NetworkError {
    var allowsStoreChatFallbackToOpponent: Bool {
        switch self {
        case .invalidRequest, .abnormalRequest:
            return true
        default:
            return false
        }
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
