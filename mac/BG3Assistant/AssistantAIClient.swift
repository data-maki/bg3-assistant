import Foundation

struct AssistantAIMessage: Sendable {
    let role: String
    let content: String
}

struct AssistantAIClient: Sendable {
    static let openRouterModel = "google/gemini-3-flash-preview"

    func complete(
        provider: AIProvider,
        messages: [AssistantAIMessage],
        imageData: Data? = nil,
        jsonSchema: Data? = nil,
        temperature: Double = 0.1,
        maxTokens: Int = 1_200,
        ollamaRuntime: OllamaRuntime
    ) async throws -> String {
        switch provider {
        case .localGemma, .localQwen:
            guard let model = provider.ollamaModel else {
                throw AIProviderError.providerNotConfigured
            }
            guard imageData == nil || provider.supportsImages else {
                throw AIProviderError.runtimeUnavailable("Qwen3 4B cannot read screenshots.")
            }
            try await ollamaRuntime.ensureReady(model: model)
            return try await completeWithOllama(
                model: model,
                messages: messages,
                imageData: imageData,
                jsonSchema: jsonSchema,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .openRouter:
            guard let key = try CredentialStore.openRouterKey(), !key.isEmpty else {
                throw AIProviderError.missingOpenRouterKey
            }
            return try await completeWithOpenRouter(
                messages: messages,
                imageData: imageData,
                jsonSchema: jsonSchema,
                temperature: temperature,
                maxTokens: maxTokens,
                key: key
            )
        }
    }

    private func completeWithOllama(
        model: String,
        messages: [AssistantAIMessage],
        imageData: Data?,
        jsonSchema: Data?,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "messages": Self.ollamaMessages(messages, imageData: imageData),
            "options": ["temperature": temperature, "num_ctx": 32_768, "num_predict": maxTokens],
        ]
        if let jsonSchema { body["format"] = try JSONSerialization.jsonObject(with: jsonSchema) }
        let data = try await postJSON(
            to: OllamaRuntime.baseURL.appending(path: "api/chat"),
            body: body,
            headers: [:],
            timeout: 180
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let content = message["content"] as? String else { throw AIProviderError.invalidResponse }
        return content
    }

    static func ollamaMessages(_ messages: [AssistantAIMessage], imageData: Data?) -> [[String: Any]] {
        var encodedMessages: [[String: Any]] = messages.map { ["role": $0.role, "content": $0.content] }
        if let imageData, let lastIndex = encodedMessages.indices.last {
            encodedMessages[lastIndex]["images"] = [imageData.base64EncodedString()]
        }
        return encodedMessages
    }

    private func completeWithOpenRouter(
        messages: [AssistantAIMessage],
        imageData: Data?,
        jsonSchema: Data?,
        temperature: Double,
        maxTokens: Int,
        key: String
    ) async throws -> String {
        var encodedMessages: [[String: Any]] = messages.map { ["role": $0.role, "content": $0.content] }
        if let imageData, let lastIndex = encodedMessages.indices.last {
            let text = encodedMessages[lastIndex]["content"] as? String ?? ""
            encodedMessages[lastIndex]["content"] = [
                ["type": "text", "text": text],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"]],
            ]
        }
        var body: [String: Any] = [
            "model": Self.openRouterModel,
            "messages": encodedMessages,
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
        if let jsonSchema {
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "assistant_response",
                    "strict": true,
                    "schema": try JSONSerialization.jsonObject(with: jsonSchema),
                ],
            ]
        }
        let data = try await postJSON(
            to: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
            body: body,
            headers: [
                "Authorization": "Bearer \(key)",
                "HTTP-Referer": "https://github.com/jcarbs/bg3_assistant",
                "X-Title": "BG3 Overlay",
            ],
            timeout: 90
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        if let content = message["content"] as? String { return content }
        if let parts = message["content"] as? [[String: Any]] {
            let content = parts.compactMap { $0["text"] as? String }.joined()
            if !content.isEmpty { return content }
        }
        throw AIProviderError.invalidResponse
    }

    private func postJSON(
        to url: URL,
        body: [String: Any],
        headers: [String: String],
        timeout: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP request failed."
            throw AIProviderError.requestFailed(String(detail.prefix(500)))
        }
        return data
    }
}
