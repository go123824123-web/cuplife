import SwiftUI

struct SettingsView: View {
    @AppStorage("openRouterAPIKey") private var openRouterKey = ""
    @AppStorage("nvidiaNIMAPIKey") private var nvidiaNIMKey = ""
    @AppStorage("selectedModelID") private var selectedModelID = AIModel.defaultModel.id
    @AppStorage("openClawPort") private var openClawPort: Int = 18789
    @AppStorage("openClawToken") private var openClawToken = ""
    @AppStorage("openClawAgentId") private var openClawAgentId = "main"
    @AppStorage("openClawSessionKey") private var openClawSessionKey = "agent:main:main"
    @Environment(\.dismiss) private var dismiss

    @State private var isOpenRouterKeyVisible = false
    @State private var isNvidiaKeyVisible = false
    @State private var isOpenClawTokenVisible = false
    @State private var testingProvider: APIProvider?
    @State private var testResult: (provider: APIProvider, success: Bool, message: String)?
    @State private var openClawPortString = ""

    var body: some View {
        NavigationStack {
            Form {
                openRouterKeySection
                nvidiaNIMKeySection
                openClawSection
                modelSection
                dangerZoneSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .onAppear {
                openClawPortString = openClawPort > 0 ? "\(openClawPort)" : "18789"
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .frame(minWidth: 420, minHeight: 580)
            #endif
        }
    }

    // MARK: - OpenRouter API Key

    private var openRouterKeySection: some View {
        Section {
            apiKeyField(
                text: $openRouterKey,
                isVisible: $isOpenRouterKeyVisible,
                provider: .openRouter
            )
        } header: {
            Text("OpenRouter API Key")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("从 openrouter.ai 获取，格式如 sk-or-v1-...")
                testResultLabel(for: .openRouter)
            }
        }
    }

    // MARK: - NVIDIA NIM API Key

    private var nvidiaNIMKeySection: some View {
        Section {
            apiKeyField(
                text: $nvidiaNIMKey,
                isVisible: $isNvidiaKeyVisible,
                provider: .nvidiaNIM
            )
        } header: {
            Text("NVIDIA NIM API Key")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("从 build.nvidia.com 获取，格式如 nvapi-...")
                testResultLabel(for: .nvidiaNIM)
            }
        }
    }

    // MARK: - OpenClaw

    private var openClawSection: some View {
        Section {
            // Port
            HStack {
                Text("端口")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("18789", text: $openClawPortString)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .frame(width: 80)
                    .onChange(of: openClawPortString) { newValue in
                        if let port = Int(newValue), port > 0, port < 65536 {
                            openClawPort = port
                        }
                    }
            }

            // Auth Token (optional)
            HStack {
                Group {
                    if isOpenClawTokenVisible {
                        TextField("Auth Token（可选）", text: $openClawToken)
                    } else {
                        SecureField("Auth Token（可选）", text: $openClawToken)
                    }
                }
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

                Button {
                    isOpenClawTokenVisible.toggle()
                } label: {
                    Image(systemName: isOpenClawTokenVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            // Agent ID
            HStack {
                Text("Agent ID")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("main", text: $openClawAgentId)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .frame(width: 120)
            }

            // Session Key
            HStack {
                Text("Session Key")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("agent:main:main", text: $openClawSessionKey)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .frame(width: 160)
            }

            // Test button
            Button {
                testOpenClaw()
            } label: {
                if testingProvider == .openClaw {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("测试连接")
                }
            }
            .buttonStyle(.borderless)
            .disabled(testingProvider != nil)

        } header: {
            Text("OpenClaw")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("连接本机运行的 OpenClaw Gateway（ws://127.0.0.1:{端口}）")
                    .foregroundStyle(.secondary)
                Text("Auth Token 仅在 Gateway 开启认证时填写")
                    .foregroundStyle(.secondary)
                testResultLabel(for: .openClaw)
            }
        }
    }

    private func testOpenClaw() {
        testingProvider = .openClaw
        testResult = nil
        let port = openClawPort > 0 ? openClawPort : 18789
        let token = openClawToken

        Task {
            do {
                try await OpenClawService.shared.testConnection(port: port, token: token)
                testResult = (.openClaw, true, "连接成功")
            } catch {
                testResult = (.openClaw, false, error.localizedDescription)
            }
            testingProvider = nil
        }
    }

    // MARK: - API Key Field

    private func apiKeyField(
        text: Binding<String>,
        isVisible: Binding<Bool>,
        provider: APIProvider
    ) -> some View {
        HStack {
            Group {
                if isVisible.wrappedValue {
                    TextField("输入 API Key", text: text)
                } else {
                    SecureField("输入 API Key", text: text)
                }
            }
            .textFieldStyle(.plain)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Button {
                testAPIKey(provider: provider)
            } label: {
                if testingProvider == provider {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("测试")
                }
            }
            .buttonStyle(.borderless)
            .disabled(text.wrappedValue.isEmpty || testingProvider != nil)
        }
    }

    // MARK: - Test Result

    @ViewBuilder
    private func testResultLabel(for provider: APIProvider) -> some View {
        if let result = testResult, result.provider == provider {
            HStack(spacing: 4) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                Text(result.message)
            }
            .foregroundStyle(result.success ? .green : .red)
        }
    }

    private func testAPIKey(provider: APIProvider) {
        testingProvider = provider
        testResult = nil

        Task {
            do {
                let testModel: AIModel
                switch provider {
                case .openRouter:
                    testModel = AIModel.openRouterFreeModels[0]
                case .nvidiaNIM:
                    testModel = AIModel.nvidiaNIMModels[0]
                case .openClaw:
                    // OpenClaw is tested via testOpenClaw(), not here
                    testingProvider = nil
                    return
                }

                let messages = [ChatCompletionMessage(role: "user", content: "Hi")]
                _ = try await ChatAPIService.shared.sendCompletion(
                    messages: messages,
                    model: testModel
                )
                testResult = (provider, true, "连接成功")
            } catch {
                testResult = (provider, false, error.localizedDescription)
            }
            testingProvider = nil
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        Section {
            Picker("当前模型", selection: $selectedModelID) {
                Section("OpenRouter · 免费") {
                    ForEach(AIModel.openRouterFreeModels) { model in
                        ModelRow(model: model).tag(model.id)
                    }
                }
                Section("OpenRouter · 付费") {
                    ForEach(AIModel.openRouterPaidModels) { model in
                        ModelRow(model: model).tag(model.id)
                    }
                }
                Section("NVIDIA NIM · 免费") {
                    ForEach(AIModel.nvidiaNIMModels) { model in
                        ModelRow(model: model).tag(model.id)
                    }
                }
                Section("OpenClaw · 本地") {
                    ForEach(AIModel.openClawModels) { model in
                        ModelRow(model: model).tag(model.id)
                    }
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("AI 模型")
        } footer: {
            Text("付费模型价格为 输入/输出 每百万 Token (USD)；OpenClaw 为本地 Agent，需 Gateway 运行中")
        }
    }

    // MARK: - Danger Zone

    @State private var showDeleteConfirm = false

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("清空所有聊天记录", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .confirmationDialog(
                "确定要清空所有聊天记录吗？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("清空", role: .destructive) {
                    deleteAllMessages()
                }
            } message: {
                Text("此操作不可撤销，所有设备上的聊天记录都会被删除。")
            }
        } header: {
            Text("数据管理")
        }
    }

    private func deleteAllMessages() {
        Task {
            try? await CloudKitService.shared.deleteAllMessages()
            NotificationCenter.default.post(name: .chatHistoryCleared, object: nil)
        }
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: AIModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                Text(model.provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.priceLabel)
                .font(.caption)
                .foregroundStyle(model.isFree ? .green : .secondary)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let chatHistoryCleared = Notification.Name("chatHistoryCleared")
}
