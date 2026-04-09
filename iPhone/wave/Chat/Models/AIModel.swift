import Foundation

struct AIModel: Identifiable, Hashable, Codable {
    /// Unique ID: "apiProvider:modelID" (e.g. "nvidiaNIM:moonshotai/kimi-k2.5")
    let id: String
    let name: String
    let provider: String
    let isFree: Bool
    let inputPrice: Double   // USD per million tokens
    let outputPrice: Double  // USD per million tokens
    let apiProvider: APIProvider

    /// The model ID sent to the API (without provider prefix)
    var modelID: String {
        guard let range = id.range(of: ":", options: .literal),
              APIProvider.allCases.contains(where: { id.hasPrefix($0.rawValue + ":") })
        else { return id }
        return String(id[range.upperBound...])
    }

    var priceLabel: String {
        if isFree { return "Free" }
        return "$\(formatPrice(inputPrice)) / $\(formatPrice(outputPrice))"
    }

    private func formatPrice(_ value: Double) -> String {
        if value < 1 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.0f", value)
    }

    init(modelID: String, name: String, provider: String, isFree: Bool,
         inputPrice: Double, outputPrice: Double, apiProvider: APIProvider) {
        self.id = "\(apiProvider.rawValue):\(modelID)"
        self.name = name
        self.provider = provider
        self.isFree = isFree
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.apiProvider = apiProvider
    }
}

// MARK: - Available Models

extension AIModel {
    static let availableModels: [AIModel] = openRouterModels + nvidiaNIMModels + openClawModels

    // MARK: OpenRouter

    static let openRouterModels: [AIModel] = openRouterFreeModels + openRouterPaidModels

    static let openRouterFreeModels: [AIModel] = [
        AIModel(
            modelID: "deepseek/deepseek-r1-0528:free",
            name: "DeepSeek R1",
            provider: "DeepSeek",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "qwen/qwen3-coder:free",
            name: "Qwen3 Coder",
            provider: "Alibaba",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "moonshotai/kimi-k2:free",
            name: "Kimi K2",
            provider: "Moonshot",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "meta-llama/llama-3.3-70b-instruct:free",
            name: "Llama 3.3 70B",
            provider: "Meta",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "nvidia/nemotron-3-nano-30b-a3b:free",
            name: "Nemotron 30B",
            provider: "NVIDIA",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "google/gemma-3-27b-it:free",
            name: "Gemma 3 27B",
            provider: "Google",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "mistralai/mistral-small-3.1-24b-instruct:free",
            name: "Mistral Small 3.1",
            provider: "Mistral",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "nousresearch/hermes-3-llama-3.1-405b:free",
            name: "Hermes 3 405B",
            provider: "Nous Research",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openRouter
        ),
    ]

    // Prices: USD per million tokens (input / output)
    static let openRouterPaidModels: [AIModel] = [
        AIModel(
            modelID: "deepseek/deepseek-v3.2",
            name: "DeepSeek V3",
            provider: "DeepSeek",
            isFree: false, inputPrice: 0.25, outputPrice: 0.38,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "google/gemini-2.0-flash-001",
            name: "Gemini 2.0 Flash",
            provider: "Google",
            isFree: false, inputPrice: 0.10, outputPrice: 0.40,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "deepseek/deepseek-r1",
            name: "DeepSeek R1",
            provider: "DeepSeek",
            isFree: false, inputPrice: 0.70, outputPrice: 2.50,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "qwen/qwen3-235b-a22b",
            name: "Qwen3 235B",
            provider: "Alibaba",
            isFree: false, inputPrice: 0.30, outputPrice: 1.20,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "moonshotai/kimi-k2.5",
            name: "Kimi K2.5",
            provider: "Moonshot",
            isFree: false, inputPrice: 0.45, outputPrice: 2.20,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "openai/gpt-4o",
            name: "GPT-4o",
            provider: "OpenAI",
            isFree: false, inputPrice: 2.50, outputPrice: 10.00,
            apiProvider: .openRouter
        ),
        AIModel(
            modelID: "anthropic/claude-sonnet-4.5",
            name: "Claude Sonnet 4.5",
            provider: "Anthropic",
            isFree: false, inputPrice: 3.00, outputPrice: 15.00,
            apiProvider: .openRouter
        ),
    ]

    // MARK: NVIDIA NIM (all free)

    static let nvidiaNIMModels: [AIModel] = [
        AIModel(
            modelID: "moonshotai/kimi-k2.5",
            name: "Kimi K2.5",
            provider: "Moonshot",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "deepseek-ai/deepseek-v3.2",
            name: "DeepSeek V3.2",
            provider: "DeepSeek",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "z-ai/glm5",
            name: "GLM-5",
            provider: "Zhipu AI",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "qwen/qwen3-coder-480b-a35b-instruct",
            name: "Qwen3 Coder 480B",
            provider: "Alibaba",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "nvidia/llama-3.3-nemotron-super-49b-v1.5",
            name: "Nemotron Super 49B",
            provider: "NVIDIA",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "openai/gpt-oss-120b",
            name: "GPT-OSS 120B",
            provider: "OpenAI",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "minimaxai/minimax-m2",
            name: "MiniMax M2",
            provider: "MiniMax",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "stepfun-ai/step-3.5-flash",
            name: "Step 3.5 Flash",
            provider: "StepFun",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
        AIModel(
            modelID: "moonshotai/kimi-k2-thinking",
            name: "Kimi K2 Thinking",
            provider: "Moonshot",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .nvidiaNIM
        ),
    ]

    // MARK: OpenClaw (local agent, WebSocket)

    static let openClawModels: [AIModel] = [
        AIModel(
            modelID: "agent",
            name: "OpenClaw Agent",
            provider: "OpenClaw",
            isFree: true, inputPrice: 0, outputPrice: 0,
            apiProvider: .openClaw
        ),
    ]

    static let defaultModel = openRouterFreeModels[0]

    static func find(byID id: String) -> AIModel? {
        availableModels.first { $0.id == id }
    }
}
