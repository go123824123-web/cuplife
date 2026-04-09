import SwiftUI

struct MessageInputView: View {
    @Binding var text: String
    let isAIResponding: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("输入消息...", text: $text)
                .textFieldStyle(.plain)
                .onSubmit { if !isAIResponding { onSend() } }
                #if os(macOS)
                .frame(minHeight: 30)
                #endif

            if isAIResponding {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isEmpty ? .gray : .accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(isEmpty)
            }
        }
        .padding()
    }
}
