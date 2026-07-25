import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case localGemma
    case localQwen
    case openRouter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localGemma: "Local Gemma 4 12B"
        case .localQwen: "Local Qwen3 4B"
        case .openRouter: "OpenRouter"
        }
    }

    var detail: String {
        switch self {
        case .localGemma: "Private and local. Reads screenshots after a 7.6 GB download."
        case .localQwen: "Private and local. Smaller 2.5 GB download, but text only."
        case .openRouter: "Uses your own API key and OpenRouter credits."
        }
    }

    var ollamaModel: String? {
        switch self {
        case .localGemma: "gemma4:12b"
        case .localQwen: "qwen3:4b"
        case .openRouter: nil
        }
    }

    var modelDownloadSize: String? {
        switch self {
        case .localGemma: "7.6 GB"
        case .localQwen: "2.5 GB"
        case .openRouter: nil
        }
    }

    var isLocal: Bool { ollamaModel != nil }

    var supportsImages: Bool {
        switch self {
        case .localGemma, .openRouter: true
        case .localQwen: false
        }
    }
}

enum AIProviderError: LocalizedError {
    case providerNotConfigured
    case missingOpenRouterKey
    case invalidResponse
    case requestFailed(String)
    case modelNotInstalled(String)
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured: "Choose Local Gemma 4 12B, Local Qwen 4B, or OpenRouter in Settings."
        case .missingOpenRouterKey: "Enter an OpenRouter API key in Settings."
        case .invalidResponse: "The AI provider returned an invalid response."
        case .requestFailed(let detail): "The AI request failed: \(detail)"
        case .modelNotInstalled(let model): "\(model) is not installed yet."
        case .runtimeUnavailable(let detail): "Local AI is unavailable: \(detail)"
        }
    }
}
