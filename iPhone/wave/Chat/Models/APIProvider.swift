import Foundation

enum APIProvider: String, Codable, CaseIterable, Hashable {
    case openRouter
    case nvidiaNIM
    /// Local OpenClaw Gateway (WebSocket, not HTTP)
    case openClaw

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .nvidiaNIM: return "NVIDIA NIM"
        case .openClaw: return "OpenClaw"
        }
    }

    var baseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .nvidiaNIM: return "https://integrate.api.nvidia.com/v1"
        case .openClaw: return "ws://127.0.0.1:18789"
        }
    }

    var apiKeyStorageKey: String {
        switch self {
        case .openRouter: return "openRouterAPIKey"
        case .nvidiaNIM: return "nvidiaNIMAPIKey"
        case .openClaw: return "openClawToken"
        }
    }

    var apiKey: String {
        UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? ""
    }
}
