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
    private var activeNamespace: String?
    private var lifecycle: SocketLifecycleState = .disconnected
    private var connectionGeneration = 0

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
        if lifecycle.roomID == roomID {
            switch lifecycle {
            case .connecting, .connected:
                Logger.shared.debug("[ChatSocket] connect ignored roomId=\(roomID) reason=already-active")
                return
            case .disconnecting:
                Logger.shared.debug("[ChatSocket] connect ignored roomId=\(roomID) reason=disconnecting")
                return
            case .disconnected:
                break
            }
        }

        if lifecycle.roomID != nil {
            disconnect()
        }
        connectionGeneration += 1
        let generation = connectionGeneration
        lifecycle = .connecting(roomID: roomID)

        guard configuration.hasValidSeSACKey else {
            lifecycle = .disconnected
            throw NetworkError.configuration(configuration.seSACKeyError ?? .missingSeSACKey)
        }
        guard let originURL = try makeSocketOriginURL() else {
            lifecycle = .disconnected
            throw NetworkError.configuration(configuration.baseURLError ?? .missingBaseURL)
        }
        let tokens = try await tokenStore.loadTokens()
        guard generation == connectionGeneration, lifecycle == .connecting(roomID: roomID) else {
            Logger.shared.debug("[ChatSocket] connect ignored roomId=\(roomID) reason=staleTokenLoad")
            return
        }
        guard let accessToken = tokens?.accessToken, !accessToken.isEmpty else {
            lifecycle = .disconnected
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
        activeNamespace = namespace
        lifecycle = .connected(roomID: roomID)

        socket.connect()
    }

    func disconnect() {
        guard socket != nil || manager != nil || lifecycle.roomID != nil else {
            Logger.shared.debug("[ChatSocket] disconnect skipped reason=alreadyDisconnected roomId=nil")
            return
        }
        if case .disconnecting(let roomID) = lifecycle {
            Logger.shared.debug("[ChatSocket] disconnect skipped reason=alreadyDisconnecting roomId=\(roomID)")
            return
        }

        let roomID = lifecycle.roomID
        let namespace = activeNamespace
        connectionGeneration += 1
        if let roomID {
            lifecycle = .disconnecting(roomID: roomID)
        }
        // Do not call removeAllHandlers() here. Socket.IO can be delivering a
        // callback while this lifecycle cleanup runs, and mutating its internal
        // handler set during enumeration is the crash we need to avoid.
        socket?.disconnect()
        manager?.disconnect()
        socket = nil
        manager = nil
        activeNamespace = nil
        lifecycle = .disconnected

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
            Task { @MainActor [weak self] in
                guard self?.lifecycle == .connected(roomID: roomID) else {
                    Logger.shared.debug("[ChatSocket] stale event ignored type=connect roomId=\(roomID)")
                    return
                }
                Logger.shared.debug("[ChatSocket] connected namespace=\(namespace)")
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, _ in
            Task { @MainActor in
                let reason = data.first.map(String.init(describing:)) ?? "unknown"
                let lifecycleReason = self?.lifecycle == .disconnecting(roomID: roomID) ? "clientRequested" : "serverOrTransport"
                Logger.shared.debug(
                    "[ChatSocket] disconnected reason=\(reason) lifecycleReason=\(lifecycleReason) namespace=\(namespace)"
                )
            }
        }

        socket.on(clientEvent: .error) { data, _ in
            let message = data.map(String.init(describing:)).joined(separator: " ")
            Logger.shared.warning("[ChatSocket] error=\(message)")
        }

        socket.on("chat") { [weak self] data, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.lifecycle == .connected(roomID: roomID) else {
                    Logger.shared.debug("[ChatSocket] stale event ignored type=chat roomId=\(roomID)")
                    return
                }
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

private enum SocketLifecycleState: Equatable {
    case disconnected
    case connecting(roomID: String)
    case connected(roomID: String)
    case disconnecting(roomID: String)

    var roomID: String? {
        switch self {
        case .disconnected:
            return nil
        case .connecting(let roomID), .connected(let roomID), .disconnecting(let roomID):
            return roomID
        }
    }
}
