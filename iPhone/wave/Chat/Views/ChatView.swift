import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showSettings = false
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            MessageInputView(
                text: $viewModel.inputText,
                isAIResponding: viewModel.isAIResponding,
                onSend: viewModel.send,
                onCancel: viewModel.cancelAIResponse
            )
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 对话")
                    .font(.headline)
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.iCloudAvailable ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.iCloudAvailable ? "iCloud 已连接" : "iCloud 未连接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(viewModel.selectedModelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button(action: viewModel.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    if viewModel.messages.isEmpty && !viewModel.isLoading {
                        WelcomeGuideView(onOpenSettings: { showSettings = true })
                            .padding()
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }

                    if viewModel.isAIResponding {
                        streamingBubble
                            .id("streaming")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.streamingText) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // MARK: - Streaming Bubble

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text(viewModel.selectedModelName)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                Group {
                    if viewModel.streamingText.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else {
                        Text(viewModel.streamingText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Spacer(minLength: 60)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let targetID: String = viewModel.isAIResponding
            ? "streaming"
            : (viewModel.messages.last?.id ?? "")
        guard !targetID.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(targetID, anchor: .bottom)
        }
    }
}

// MARK: - Welcome Guide（空状态引导）

private struct WelcomeGuideView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // 标题
            VStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("欢迎使用 AI 对话")
                    .font(.title2.bold())
                Text("选择以下任意一种方式开始对话")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            // 方式一：在线 AI 模型
            GuideCard(
                icon: "cloud",
                iconColor: .blue,
                title: "方式一  在线 AI 模型",
                subtitle: "通过 OpenRouter 或 NVIDIA NIM 调用云端大模型",
                steps: [
                    "点击右上角 ⚙ 打开设置",
                    "在「OpenRouter API Key」中填入你的 Key（格式 sk-or-v1-...）",
                    "或在「NVIDIA NIM API Key」中填入 Key（格式 nvapi-...）",
                    "在「AI 模型」中选择想用的模型",
                    "回到主界面，直接发送消息即可"
                ],
                tip: "OpenRouter 和 NVIDIA NIM 均有免费模型，无需付费即可使用"
            )

            // 方式二：OpenClaw 本地 Agent
            GuideCard(
                icon: "desktopcomputer",
                iconColor: .orange,
                title: "方式二  本地 OpenClaw Agent",
                subtitle: "直接与本机运行的 OpenClaw AI Agent 对话，无需 API Key",
                steps: [
                    "确认本机 OpenClaw Gateway 正在运行（默认端口 18789）",
                    "点击右上角 ⚙ 打开设置",
                    "在「OpenClaw」区域确认端口号（一般保持 18789）",
                    "点击「测试连接」，看到「连接成功」即可",
                    "在「AI 模型」→「OpenClaw · 本地」中选择 OpenClaw Agent",
                    "回到主界面，直接发送消息即可"
                ],
                tip: "如果 Gateway 开启了认证，需在「Auth Token」中填写对应的 Token"
            )

            Button(action: onOpenSettings) {
                Label("打开设置", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 460)
    }
}

// MARK: - Guide Card

private struct GuideCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let steps: [String]
    let tip: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题行
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text(title)
                    .font(.subheadline.bold())
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // 步骤列表
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(iconColor.opacity(0.75))
                            .clipShape(Circle())
                        Text(step)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 提示
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(tip)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Help View（? 按钮打开的完整帮助页）

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WelcomeGuideView(onOpenSettings: { dismiss() })
                }
                .padding()
            }
            .navigationTitle("使用说明")
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
            .frame(minWidth: 520, minHeight: 600)
            #endif
        }
    }
}
