import Foundation

final class ChatAPIService: Sendable {
    static let shared = ChatAPIService()

    private init() {}

    // MARK: - Streaming

    func streamCompletion(
        messages: [ChatCompletionMessage],
        model: AIModel,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let apiKey = model.apiProvider.apiKey
        guard !apiKey.isEmpty else {
            throw ChatAPIError.missingAPIKey(model.apiProvider)
        }

        let request = try buildRequest(
            provider: model.apiProvider,
            apiKey: apiKey,
            body: RequestBody(model: model.modelID, messages: messages, stream: true)
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validateHTTPResponse(response)

        var fullContent = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload.trimmed == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta.content
            else { continue }

            fullContent += delta
            onPartial(fullContent)
        }

        guard !fullContent.isEmpty else { throw ChatAPIError.emptyResponse }
        return fullContent
    }

    // MARK: - Non-Streaming

    func sendCompletion(
        messages: [ChatCompletionMessage],
        model: AIModel
    ) async throws -> String {
        let apiKey = model.apiProvider.apiKey
        guard !apiKey.isEmpty else {
            throw ChatAPIError.missingAPIKey(model.apiProvider)
        }

        let request = try buildRequest(
            provider: model.apiProvider,
            apiKey: apiKey,
            body: RequestBody(model: model.modelID, messages: messages, stream: false)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data)

        let result = try JSONDecoder().decode(CompletionResponse.self, from: data)
        guard let content = result.choices.first?.message.content else {
            throw ChatAPIError.emptyResponse
        }
        return content
    }

    // MARK: - Helpers

    private func buildRequest(provider: APIProvider, apiKey: String, body: RequestBody) throws -> URLRequest {
        let url = URL(string: "\(provider.baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .openRouter {
            request.setValue("Wave", forHTTPHeaderField: "X-Title")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
            throw ChatAPIError.apiError(statusCode: http.statusCode, message: body)
        }
    }
}

// MARK: - Request / Response Types

struct ChatCompletionMessage: Codable, Sendable {
    let role: String
    let content: String
}

extension ChatAPIService {
    struct RequestBody: Codable {
        let model: String
        let messages: [ChatCompletionMessage]
        let stream: Bool
    }

    struct CompletionResponse: Codable {
        let choices: [Choice]

        struct Choice: Codable {
            let message: ChatCompletionMessage
        }
    }

    struct StreamChunk: Codable {
        let choices: [StreamChoice]

        struct StreamChoice: Codable {
            let delta: Delta
        }

        struct Delta: Codable {
            let content: String?
        }
    }
}

// MARK: - Errors

enum ChatAPIError: LocalizedError {
    case missingAPIKey(APIProvider)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "请在设置中填写 \(provider.displayName) API Key"
        case .invalidResponse:
            return "服务器返回了无效响应"
        case .apiError(let code, let message):
            return "API 错误 (\(code)): \(message)"
        case .emptyResponse:
            return "AI 未返回任何内容"
        }
    }
}

// MARK: - String Helpers

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
