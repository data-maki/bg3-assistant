import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case localQwen
    case openRouter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localQwen: "Local Qwen 4B"
        case .openRouter: "OpenRouter"
        }
    }

    var detail: String {
        switch self {
        case .localQwen: "Private and offline after a 2.5 GB model download."
        case .openRouter: "Uses your own API key and OpenRouter credits."
        }
    }

    var supportsImages: Bool { self == .openRouter }
}

enum AIProviderError: LocalizedError {
    case providerNotConfigured
    case missingOpenRouterKey
    case invalidResponse
    case requestFailed(String)
    case modelNotInstalled
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured: "Choose Local Qwen 4B or OpenRouter in Settings."
        case .missingOpenRouterKey: "Enter an OpenRouter API key in Settings."
        case .invalidResponse: "The AI provider returned an invalid response."
        case .requestFailed(let detail): "The AI request failed: \(detail)"
        case .modelNotInstalled: "Qwen3 4B is not installed yet."
        case .runtimeUnavailable(let detail): "Local AI is unavailable: \(detail)"
        }
    }
}
