import Foundation

struct ChatParticipant: Equatable, Sendable, Identifiable {
    let id: String
    let nick: String
    let profileImagePath: String?
}

struct ChatMessage: Equatable, Sendable, Identifiable {
    let id: String
    let roomID: String
    let content: String
    let createdAt: Date?
    let updatedAt: Date?
    let sender: ChatParticipant
    let filePaths: [String]
}

struct ChatRoom: Equatable, Sendable, Identifiable {
    let id: String
    let createdAt: Date?
    let updatedAt: Date?
    let participants: [ChatParticipant]
    let lastMessage: ChatMessage?
}

struct CreateChatRoomRequestDTO: Encodable, Sendable {
    let opponentID: String

    private enum CodingKeys: String, CodingKey {
        case opponentID = "opponent_id"
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

protocol ChatRemoteDataSourceProtocol: Sendable {
    func fetchChatRooms() async throws -> ChatRoomListResponseDTO
    func createOrFetchChatRoom(opponentID: String) async throws -> ChatRoomDTO
    func fetchMessages(roomID: String, next: String?) async throws -> ChatMessageListResponseDTO
    func sendMessage(roomID: String, content: String, files: [String]) async throws -> ChatMessageDTO
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

    func createOrFetchChatRoom(opponentID: String) async throws -> ChatRoomDTO {
        let body = RequestBody.json(
            try NetworkCoding.makeJSONEncoder().encode(
                CreateChatRoomRequestDTO(opponentID: opponentID)
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
}

protocol ChatRepository: Sendable {
    func fetchChatRooms() async throws -> [ChatRoom]
    func createOrFetchChatRoom(opponentID: String) async throws -> ChatRoom
    func fetchMessages(roomID: String, next: String?) async throws -> [ChatMessage]
    func sendMessage(roomID: String, content: String) async throws -> ChatMessage
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

    func createOrFetchChatRoom(opponentID: String) async throws -> ChatRoom {
        let response = try await remoteDataSource.createOrFetchChatRoom(opponentID: opponentID)
        return mapper.mapRoom(response)
    }

    func fetchMessages(roomID: String, next: String?) async throws -> [ChatMessage] {
        try await remoteDataSource.fetchMessages(roomID: roomID, next: next).data.map(mapper.mapMessage)
    }

    func sendMessage(roomID: String, content: String) async throws -> ChatMessage {
        let response = try await remoteDataSource.sendMessage(roomID: roomID, content: content, files: [])
        return mapper.mapMessage(response)
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

enum ChatFeatureError: Error, Equatable {
    case authenticationRequired
    case unavailable(message: String)
}

extension ChatFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 채팅을 이용할 수 있어요."
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
protocol ChatInteracting {
    var currentUserID: String? { get }
    var startsFromStore: Bool { get }

    func loadInitialRoomList() async throws -> [ChatRoom]
    func createOrFetchStoreChatRoom() async throws -> ChatRoom
    func loadMessages(roomID: String, after next: String?) async throws -> [ChatMessage]
    func sendMessage(roomID: String, content: String) async throws -> ChatMessage
}

@MainActor
struct ChatInteractor: ChatInteracting {
    let currentUserID: String?
    let startsFromStore: Bool

    private let storeID: String?
    private let chatRepository: ChatRepository
    private let storeRepository: StoreRepository
    private let sessionStore: SessionStore

    init(
        storeID: String? = nil,
        chatRepository: ChatRepository,
        storeRepository: StoreRepository,
        sessionStore: SessionStore
    ) {
        self.storeID = storeID
        self.chatRepository = chatRepository
        self.storeRepository = storeRepository
        self.sessionStore = sessionStore
        self.currentUserID = sessionStore.currentUserID
        self.startsFromStore = storeID != nil
    }

    func loadInitialRoomList() async throws -> [ChatRoom] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        do {
            return try await chatRepository.fetchChatRooms()
        } catch {
            throw map(error)
        }
    }

    func createOrFetchStoreChatRoom() async throws -> ChatRoom {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }
        guard let storeID else {
            throw ChatFeatureError.unavailable(message: "문의할 가게 정보를 찾지 못했어요.")
        }

        do {
            let store = try await storeRepository.fetchStoreDetail(storeID: storeID)
            guard let ownerID = store.owner?.id, !ownerID.isEmpty else {
                throw ChatFeatureError.unavailable(message: "가게 문의 대상을 찾지 못했어요.")
            }
            if ownerID == sessionStore.currentUserID {
                throw ChatFeatureError.unavailable(message: "내 가게에는 채팅 문의를 보낼 수 없어요.")
            }
            return try await chatRepository.createOrFetchChatRoom(opponentID: ownerID)
        } catch let error as ChatFeatureError {
            throw error
        } catch {
            throw map(error)
        }
    }

    func loadMessages(roomID: String, after next: String? = nil) async throws -> [ChatMessage] {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }

        do {
            return try await chatRepository.fetchMessages(roomID: roomID, next: next)
        } catch {
            throw map(error)
        }
    }

    func sendMessage(roomID: String, content: String) async throws -> ChatMessage {
        guard sessionStore.isAuthenticated else {
            throw ChatFeatureError.authenticationRequired
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ChatFeatureError.unavailable(message: "메시지를 입력해 주세요.")
        }

        do {
            return try await chatRepository.sendMessage(roomID: roomID, content: trimmed)
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
            return .unavailable(message: "채팅 응답을 해석하지 못했어요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }
}
