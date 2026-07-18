import Foundation

struct BackendClient {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    func health() async -> Bool {
        await healthDetails()?.ok == true
    }

    func healthDetails() async -> BackendHealth? {
        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try decoder.decode(BackendHealth.self, from: data)
        } catch { return nil }
    }

    static func guidePath(for act: Int) -> String { "api/acts/\(act)/guide" }

    func route(act: Int) async throws -> RoutePayload {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: Self.guidePath(for: act)))
        try validate(response, data: data)
        return try decoder.decode(RoutePayload.self, from: data)
    }

    func items() async throws -> [ItemSummary] {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "api/items"))
        try validate(response, data: data)
        return try decoder.decode([ItemSummary].self, from: data)
    }

    func chat(_ requestBody: ChatRequest) async throws -> ChatResponse {
        try await postJSON(path: "api/chat", body: requestBody, response: ChatResponse.self)
    }

    func importBuild(_ requestBody: LoadoutImportRequest) async throws -> ImportedBuild {
        try await postJSON(
            path: "api/builds/import", body: requestBody,
            response: ImportedBuild.self, timeout: 180
        )
    }

    private func postJSON<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        response: Response.Type,
        timeout: TimeInterval = 60
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        try validate(urlResponse, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(BackendErrorPayload.self, from: data) {
                throw BackendClientError.message(payload.detail)
            }
            throw BG3AssistantError.invalidBackendResponse
        }
    }

}

private struct BackendErrorPayload: Decodable {
    let detail: String
}

private enum BackendClientError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
