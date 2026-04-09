import Foundation

// MARK: - Errors

enum OpenClawError: LocalizedError {
    case connectionFailed(String)
    case authFailed(String)
    case sendFailed(String)
    case notConnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "OpenClaw 连接失败: \(msg)"
        case .authFailed(let msg): return "OpenClaw 认证失败: \(msg)"
        case .sendFailed(let msg): return "OpenClaw 发送失败: \(msg)"
        case .notConnected: return "OpenClaw 未连接，请在设置中检查端口并测试连接"
        case .timeout: return "OpenClaw 响应超时（120 秒）"
        }
    }
}

// MARK: - Service

/// Actor-based WebSocket client for OpenClaw Gateway.
/// Protocol: JSON over WebSocket, req/res/event message types.
/// Gateway default: ws://127.0.0.1:18789
actor OpenClawService {
    static let shared = OpenClawService()

    private(set) var port: Int = 18789
    private(set) var isConnected: Bool = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?

    /// [requestID: continuation] waiting for a "res" message
    private var pendingContinuations: [String: CheckedContinuation<[String: Any], Error>] = [:]
    /// [requestID: streaming-text callback]
    private var streamCallbacks: [String: @Sendable (String) -> Void] = [:]
    /// [requestID: accumulated streaming text]
    private var streamAccumulated: [String: String] = [:]

    private init() {}

    // MARK: - Connect

    /// Connect (or reconnect) to the local OpenClaw Gateway.
    func connect(port: Int = 18789, token: String = "") async throws {
        self.port = port
        closeSocket()

        guard let url = URL(string: "ws://127.0.0.1:\(port)") else {
            throw OpenClawError.connectionFailed("无效端口号")
        }

        let task = URLSession.shared.webSocketTask(with: URLRequest(url: url))
        webSocketTask = task
        task.resume()

        startReceiveLoop()

        // Build connect request (Gateway protocol v3)
        var auth: [String: Any] = [:]
        if !token.isEmpty { auth["token"] = token }

        let connectID = UUID().uuidString
        let params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 3,
            "client": [
                "id": "wave",
                "version": "1.0.0",
                "platform": "ios",
                "mode": "operator"
            ],
            "role": "operator",
            "scopes": ["operator.read", "operator.write"],
            "caps": [],
            "commands": [],
            "permissions": [:],
            "auth": auth,
            "locale": "zh-CN",
            "userAgent": "Wave/1.0"
        ]

        let json = try buildMessage(id: connectID, method: "connect", params: params)
        try await sendRaw(json)

        // Wait for hello-ok response
        let response = try await waitFor(id: connectID, timeout: 10)

        guard response["ok"] as? Bool == true else {
            let errMsg = (response["error"] as? [String: Any])?["message"] as? String ?? "认证失败"
            closeSocket()
            throw OpenClawError.authFailed(errMsg)
        }

        isConnected = true
    }

    // MARK: - Ensure Connected

    /// Connect if not already connected on the specified port.
    func ensureConnected(port: Int, token: String) async throws {
        if isConnected && self.port == port { return }
        try await connect(port: port, token: token)
    }

    // MARK: - Send Message

    /// Send a user message to the OpenClaw agent and stream the response.
    /// - Parameters:
    ///   - text: User's message text
    ///   - agentId: Agent ID (default "main")
    ///   - sessionKey: Session key in format "agent:{agentId}:{channel}" (default "agent:main:main")
    ///   - onPartial: Called with accumulated text as streaming tokens arrive
    /// - Returns: Full response text
    func sendMessage(
        text: String,
        agentId: String = "main",
        sessionKey: String = "agent:main:main",
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard isConnected else { throw OpenClawError.notConnected }

        let requestID = UUID().uuidString
        streamCallbacks[requestID] = onPartial
        streamAccumulated[requestID] = ""

        let params: [String: Any] = [
            "agentId": agentId,
            "sessionKey": sessionKey,
            "message": text
        ]

        let json = try buildMessage(id: requestID, method: "agent.send", params: params)
        try await sendRaw(json)

        return try await withTaskCancellationHandler {
            let response: [String: Any]
            do {
                response = try await waitFor(id: requestID, timeout: 120)
            } catch {
                streamCallbacks.removeValue(forKey: requestID)
                streamAccumulated.removeValue(forKey: requestID)
                throw error
            }

            let accumulated = streamAccumulated[requestID] ?? ""
            streamCallbacks.removeValue(forKey: requestID)
            streamAccumulated.removeValue(forKey: requestID)

            if response["ok"] as? Bool != true {
                let errMsg = (response["error"] as? [String: Any])?["message"] as? String ?? "Agent 未响应"
                throw OpenClawError.sendFailed(errMsg)
            }

            if !accumulated.isEmpty { return accumulated }

            let payload = response["payload"] as? [String: Any] ?? [:]
            return (payload["content"] as? String)
                ?? (payload["text"] as? String)
                ?? (payload["delta"] as? String)
                ?? ""
        } onCancel: {
            Task { await self.cancelRequest(id: requestID) }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        closeSocket()
    }

    // MARK: - Test

    func testConnection(port: Int, token: String) async throws {
        try await connect(port: port, token: token)
        disconnect()
    }

    // MARK: - Private: Request Handling

    private func waitFor(id: String, timeout: Double) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            pendingContinuations[id] = continuation

            // Schedule timeout cancellation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self else { return }
                await self.cancelWithTimeout(id: id)
            }
        }
    }

    private func cancelRequest(id: String) {
        if let cont = pendingContinuations.removeValue(forKey: id) {
            cont.resume(throwing: CancellationError())
        }
        streamCallbacks.removeValue(forKey: id)
        streamAccumulated.removeValue(forKey: id)
    }

    private func cancelWithTimeout(id: String) {
        if let cont = pendingContinuations.removeValue(forKey: id) {
            cont.resume(throwing: OpenClawError.timeout)
        }
        streamCallbacks.removeValue(forKey: id)
        streamAccumulated.removeValue(forKey: id)
    }

    // MARK: - Private: WebSocket

    private func startReceiveLoop() {
        receiveLoopTask?.cancel()
        receiveLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let msg = try await task.receive()
                switch msg {
                case .string(let s):
                    dispatch(raw: s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) { dispatch(raw: s) }
                @unknown default:
                    break
                }
            } catch {
                // Connection closed or error
                isConnected = false
                let err = OpenClawError.connectionFailed(error.localizedDescription)
                for (_, cont) in pendingContinuations {
                    cont.resume(throwing: err)
                }
                pendingContinuations.removeAll()
                streamCallbacks.removeAll()
                streamAccumulated.removeAll()
                break
            }
        }
    }

    private func dispatch(raw text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let msgType = json["type"] as? String ?? ""
        switch msgType {
        case "res":
            handleResponse(json)
        case "event":
            handleEvent(json)
        default:
            break
        }
    }

    private func handleResponse(_ json: [String: Any]) {
        guard let id = json["id"] as? String,
              let cont = pendingContinuations.removeValue(forKey: id)
        else { return }
        cont.resume(returning: json)
    }

    /// Handle streaming token events from the agent.
    /// OpenClaw may emit: agent.token, agent.delta, agent.chunk,
    /// message.partial, message.token, output.token, etc.
    private func handleEvent(_ json: [String: Any]) {
        let eventName = json["event"] as? String ?? ""
        guard let payload = json["payload"] as? [String: Any] else { return }

        let streamingEvents: Set<String> = [
            "agent.token", "agent.delta", "agent.chunk", "agent.stream",
            "message.partial", "message.token", "message.delta",
            "output.token", "output.delta"
        ]
        guard streamingEvents.contains(eventName) else { return }

        let token = (payload["token"] as? String)
            ?? (payload["delta"] as? String)
            ?? (payload["text"] as? String)
            ?? (payload["content"] as? String)
            ?? ""
        guard !token.isEmpty else { return }

        // Try to match to a specific pending request via requestId
        let requestID = (json["requestId"] as? String)
            ?? (payload["requestId"] as? String)

        if let rid = requestID, let callback = streamCallbacks[rid] {
            streamAccumulated[rid, default: ""] += token
            let acc = streamAccumulated[rid, default: ""]
            callback(acc)
        } else if let (firstID, callback) = streamCallbacks.first {
            // Fallback: route to the only pending callback
            streamAccumulated[firstID, default: ""] += token
            let acc = streamAccumulated[firstID, default: ""]
            callback(acc)
        }
    }

    // MARK: - Private: Utilities

    private func closeSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        isConnected = false

        let err = OpenClawError.notConnected
        for (_, cont) in pendingContinuations {
            cont.resume(throwing: err)
        }
        pendingContinuations.removeAll()
        streamCallbacks.removeAll()
        streamAccumulated.removeAll()
    }

    private func buildMessage(id: String, method: String, params: [String: Any]) throws -> String {
        let obj: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func sendRaw(_ text: String) async throws {
        guard let task = webSocketTask else { throw OpenClawError.notConnected }
        try await task.send(.string(text))
    }
}
