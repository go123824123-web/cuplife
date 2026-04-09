import Foundation
import CloudKit
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published var inputText: String = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var isAIResponding = false
    @Published private(set) var streamingText: String = ""

    private let cloudKit = CloudKitService.shared
    private let chatAPI = ChatAPIService.shared
    private var pollingTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var selectedModelID: String {
        UserDefaults.standard.string(forKey: "selectedModelID")
            ?? AIModel.defaultModel.id
    }

    var selectedModel: AIModel {
        AIModel.find(byID: selectedModelID) ?? AIModel.defaultModel
    }

    var selectedModelName: String {
        selectedModel.name
    }

    // MARK: - Lifecycle

    func startListening() {
        observePushNotifications()
        observeChatCleared()

        Task {
            await checkiCloudStatus()
            guard iCloudAvailable else { return }
            fetchAllMessages()
            startPolling()
            setupSubscription()
        }
    }

    func stopListening() {
        pollingTask?.cancel()
        pollingTask = nil
        aiTask?.cancel()
        aiTask = nil
        cancellables.removeAll()
    }

    // MARK: - Send

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard iCloudAvailable else {
            errorMessage = "请登录 iCloud 以使用 AI 对话"
            return
        }

        inputText = ""

        Task {
            do {
                let message = try await cloudKit.sendMessage(text: text, role: .user)
                appendIfNew(message)
                requestAIResponse()
            } catch {
                errorMessage = "发送失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - AI Response

    func cancelAIResponse() {
        aiTask?.cancel()
        aiTask = nil
        isAIResponding = false
        streamingText = ""
    }

    private func requestAIResponse() {
        aiTask?.cancel()
        aiTask = Task {
            isAIResponding = true
            streamingText = ""

            do {
                let model = selectedModel
                let fullContent: String

                if model.apiProvider == .openClaw {
                    fullContent = try await requestOpenClawResponse(model: model)
                } else {
                    let context = buildConversationContext()
                    fullContent = try await chatAPI.streamCompletion(
                        messages: context,
                        model: model
                    ) { partial in
                        Task { @MainActor [weak self] in
                            self?.streamingText = partial
                        }
                    }
                }

                guard !Task.isCancelled else { return }

                let aiMessage = try await cloudKit.sendMessage(
                    text: fullContent,
                    role: .assistant,
                    modelID: model.id
                )
                appendIfNew(aiMessage)
            } catch is CancellationError {
                // User cancelled, no error needed
            } catch {
                if !Task.isCancelled {
                    errorMessage = "AI 响应失败: \(error.localizedDescription)"
                }
            }

            isAIResponding = false
            streamingText = ""
        }
    }

    private func requestOpenClawResponse(model: AIModel) async throws -> String {
        let port = UserDefaults.standard.integer(forKey: "openClawPort")
        let token = UserDefaults.standard.string(forKey: "openClawToken") ?? ""
        let agentId = UserDefaults.standard.string(forKey: "openClawAgentId") ?? "main"
        let sessionKey = UserDefaults.standard.string(forKey: "openClawSessionKey") ?? "agent:main:main"
        let effectivePort = port > 0 ? port : 18789

        try await OpenClawService.shared.ensureConnected(port: effectivePort, token: token)

        let lastUserText = messages.last(where: { $0.isUser })?.text ?? ""
        return try await OpenClawService.shared.sendMessage(
            text: lastUserText,
            agentId: agentId,
            sessionKey: sessionKey
        ) { partial in
            Task { @MainActor [weak self] in
                self?.streamingText = partial
            }
        }
    }

    private func buildConversationContext() -> [ChatCompletionMessage] {
        let model = selectedModel
        let systemPrompt = ChatCompletionMessage(
            role: "system",
            content: "你是 \(model.name)，由 \(model.provider) 开发。请用中文回答。"
        )
        let recentMessages = messages.suffix(20).map { $0.toChatCompletionMessage() }
        return [systemPrompt] + recentMessages
    }

    // MARK: - Refresh

    func refresh() {
        guard iCloudAvailable else {
            Task { await checkiCloudStatus() }
            return
        }
        fetchAllMessages()
    }

    func fetchNewMessages() {
        Task {
            do {
                let fetched = try await cloudKit.fetchMessages()
                let sorted = fetched.sorted()

                if isAIResponding {
                    // AI 回答中：只追加新消息，不替换已有的（避免 CloudKit 索引延迟导致消息消失）
                    let existingIDs = Set(messages.map(\.id))
                    let newMessages = sorted.filter { !existingIDs.contains($0.id) }
                    if !newMessages.isEmpty {
                        messages.append(contentsOf: newMessages)
                        messages.sort()
                    }
                } else {
                    if sorted.map(\.id) != messages.map(\.id) {
                        messages = sorted
                    }
                }
            } catch {
                // Polling failure is silent
            }
        }
    }

    // MARK: - Private

    private func checkiCloudStatus() async {
        do {
            let status = try await cloudKit.checkAccountStatus()
            iCloudAvailable = (status == .available)
            if !iCloudAvailable {
                errorMessage = "请登录 iCloud 以使用 AI 对话"
            }
        } catch {
            errorMessage = "无法检查 iCloud 状态: \(error.localizedDescription)"
        }
    }

    private func fetchAllMessages() {
        isLoading = true
        Task {
            do {
                let fetched = try await cloudKit.fetchMessages()
                messages = fetched.sorted()
                errorMessage = nil
            } catch let error as CKError {
                errorMessage = cloudKitErrorMessage(error)
            } catch {
                errorMessage = "获取消息失败: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func cloudKitErrorMessage(_ error: CKError) -> String {
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return "CloudKit 网络不可用。请检查：\n1. 打开 iCloud.developer.apple.com 确认容器 iCloud.hikayo.wave 已创建\n2. 在 Xcode → Signing & Capabilities → iCloud 中确认 CloudKit 已勾选"
        case .notAuthenticated:
            return "iCloud 未登录，请在设置中登录 iCloud"
        case .unknownItem:
            return ""  // Record type doesn't exist yet, not an error
        default:
            return "CloudKit 错误 (\(error.code.rawValue)): \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                fetchNewMessages()
            }
        }
    }

    private func setupSubscription() {
        Task { try? await cloudKit.subscribeToChanges() }
    }

    private func observePushNotifications() {
        NotificationCenter.default
            .publisher(for: .newCloudKitMessage)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchNewMessages()
            }
            .store(in: &cancellables)
    }

    private func observeChatCleared() {
        NotificationCenter.default
            .publisher(for: .chatHistoryCleared)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.messages = []
            }
            .store(in: &cancellables)
    }

    private func appendIfNew(_ message: Message) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        messages.sort()
    }
}
