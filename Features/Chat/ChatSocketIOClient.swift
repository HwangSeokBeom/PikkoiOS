import Foundation
import SocketIO

@MainActor
final class ChatSocketIOClient: ChatRealtimeServiceProtocol {
    private let configuration: AppConfiguration
    private let tokenStore: any TokenStore
    private let mapper: ChatMapper
    private let decoder = NetworkCoding.makeJSONDecoder()

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var activeRoomID: String?
    private var activeNamespace: String?
    private var isDisconnecting = false
    private var lastDisconnectReason = "none"

    init(
        configuration: AppConfiguration,
        tokenStore: any TokenStore,
        mapper: ChatMapper
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.mapper = mapper
    }

    func connect(roomID: String, currentUserID: String?, onMessage: @escaping @MainActor (ChatMessage) async -> Void) async throws {
        if activeRoomID == roomID {
            let status = socket?.status
            if status == .connected || status == .connecting {
                Logger.shared.debug("[ChatSocket] connect ignored roomId=\(roomID) reason=already-active")
                return
            }
        }

        if activeRoomID != nil {
            disconnect()
        }

        guard configuration.hasValidSeSACKey else {
            throw NetworkError.configuration(configuration.seSACKeyError ?? .missingSeSACKey)
        }
        guard let originURL = try makeSocketOriginURL() else {
            throw NetworkError.configuration(configuration.baseURLError ?? .missingBaseURL)
        }
        let tokens = try await tokenStore.loadTokens()
        guard let accessToken = tokens?.accessToken, !accessToken.isEmpty else {
            throw NetworkError.unauthorized
        }

        let namespace = "/chats-\(roomID)"
        let authorization = configuration.authorizationHeaderFormat.format(accessToken)
        let headers = [
            "SesacKey": configuration.seSACKey,
            "Authorization": authorization
        ]

        Logger.shared.debug("[ChatSocket] implementation=Socket.IO")
        Logger.shared.debug("[ChatSocket] socketURL=\(originURL.absoluteString) namespace=\(namespace)")
        Logger.shared.debug(
            "[ChatSocket] connect requested roomId=\(roomID) hasAccessToken=\(!accessToken.isEmpty) hasSesacKey=\(!configuration.seSACKey.isEmpty)"
        )

        var socketConfig: SocketIOClientConfiguration = [
            .compress,
            .forceWebsockets(true),
            .extraHeaders(headers)
        ]
        if configuration.isChatSocketDebugEnabled {
            socketConfig.insert(.log(true))
        }

        let manager = SocketManager(socketURL: originURL, config: socketConfig)
        let socket = manager.socket(forNamespace: namespace)

        registerHandlers(socket: socket, roomID: roomID, namespace: namespace, currentUserID: currentUserID, onMessage: onMessage)

        self.manager = manager
        self.socket = socket
        activeRoomID = roomID
        activeNamespace = namespace
        lastDisconnectReason = "active"

        socket.connect()
    }

    func disconnect() {
        guard socket != nil || manager != nil else {
            return
        }
        guard !isDisconnecting else {
            return
        }
        isDisconnecting = true
        lastDisconnectReason = "clientRequested"
        defer { isDisconnecting = false }

        let namespace = activeNamespace
        socket?.removeAllHandlers()
        socket?.disconnect()
        manager?.disconnect()
        socket = nil
        manager = nil
        activeRoomID = nil
        activeNamespace = nil

        if let namespace {
            Logger.shared.debug("[ChatSocket] disconnected reason=clientRequested namespace=\(namespace)")
        }
    }

    private func registerHandlers(
        socket: SocketIOClient,
        roomID: String,
        namespace: String,
        currentUserID: String?,
        onMessage: @escaping @MainActor (ChatMessage) async -> Void
    ) {
        socket.on(clientEvent: .connect) { _, _ in
            Logger.shared.debug("[ChatSocket] connected namespace=\(namespace)")
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            let reason = data.first.map(String.init(describing:)) ?? "unknown"
            let lifecycleReason = self?.isDisconnecting == true ? "clientRequested" : "serverOrTransport"
            Logger.shared.debug(
                "[ChatSocket] disconnected reason=\(reason) lifecycleReason=\(lifecycleReason) namespace=\(namespace)"
            )
        }

        socket.on(clientEvent: .error) { data, _ in
            let message = data.map(String.init(describing:)).joined(separator: " ")
            Logger.shared.warning("[ChatSocket] error=\(message)")
        }

        socket.on("chat") { [weak self] data, _ in
            Task { @MainActor in
                guard let self else { return }
                let messages = self.decodeMessages(from: data)
                if messages.isEmpty {
                    Logger.shared.warning("[ChatSocket] chat received roomId=\(roomID) chatId=<decode-failed>")
                }

                for message in messages where message.roomID == roomID {
                    let chatID = message.effectiveServerChatID ?? message.id
                    let isMine = currentUserID != nil && message.sender.id == currentUserID
                    Logger.shared.debug("[ChatSocket] received roomId=\(roomID) chatId=\(chatID) senderId=\(message.sender.id) isMine=\(isMine)")
                    await onMessage(message)
                }
            }
        }
    }

    private func makeSocketOriginURL() throws -> URL? {
        guard let baseURL = configuration.baseURL else {
            return nil
        }
        return try URLBuilder().makeOriginURL(baseURL: baseURL)
    }

    private func decodeMessages(from data: [Any]) -> [ChatMessage] {
        data.flatMap(findChatDTOs).map(mapper.mapMessage)
    }

    private func findChatDTOs(in jsonObject: Any) -> [ChatMessageDTO] {
        if JSONSerialization.isValidJSONObject(jsonObject),
           let data = try? JSONSerialization.data(withJSONObject: jsonObject),
           let dto = try? decoder.decode(ChatMessageDTO.self, from: data) {
            return [dto]
        }

        if let array = jsonObject as? [Any] {
            return array.flatMap(findChatDTOs)
        }

        if let dictionary = jsonObject as? [String: Any] {
            return ["chat", "message", "data", "payload"].flatMap { key -> [ChatMessageDTO] in
                guard let value = dictionary[key] else { return [] }
                return findChatDTOs(in: value)
            }
        }

        return []
    }
}
