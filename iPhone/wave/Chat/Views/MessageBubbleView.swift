import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    private var isUser: Bool { message.isUser }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                senderLabel
                bubble
                timestampLabel
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var senderLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: senderIcon)
                .font(.caption2)
            Text(senderName)
                .font(.caption2)
            if let provider = senderProvider {
                Text("· \(provider)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
    }

    private var bubble: some View {
        Text(message.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isUser ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundStyle(isUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .textSelection(.enabled)
    }

    private var timestampLabel: some View {
        Text(message.timestamp, style: .time)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var senderIcon: String {
        if message.isUser {
            return message.senderDevice == "macOS" ? "laptopcomputer" : "iphone"
        }
        return "sparkles"
    }

    private var senderName: String {
        if message.isUser {
            return message.senderDevice
        }
        if let modelID = message.modelID,
           let model = AIModel.find(byID: modelID) {
            return model.name
        }
        return "AI"
    }

    private var senderProvider: String? {
        guard !message.isUser,
              let modelID = message.modelID,
              let model = AIModel.find(byID: modelID) else {
            return nil
        }
        return model.provider
    }
}
