import Foundation

struct BackendClient {
    private let endpoint: BackendEndpoint
    private let session: URLSession
    private let companionControlToken: String
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

    init(
        endpoint: BackendEndpoint,
        companionControlToken: String = "",
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.companionControlToken = companionControlToken
        self.session = session
    }

    func health() async -> Bool {
        await healthDetails()?.ok == true
    }

    func healthDetails() async -> BackendHealth? {
        do {
            var request = URLRequest(url: endpoint.url(path: "health"))
            request.timeoutInterval = 5
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let health = try decoder.decode(BackendHealth.self, from: data)
            return health.service == "bg3-honor-assistant" ? health : nil
        } catch { return nil }
    }

    static func guidePath(for act: Int) -> String { "api/acts/\(act)/guide" }

    func route(act: Int) async throws -> RoutePayload {
        let (data, response) = try await session.data(from: endpoint.url(path: Self.guidePath(for: act)))
        try validate(response, data: data)
        return try decoder.decode(RoutePayload.self, from: data)
    }

    func items() async throws -> [ItemSummary] {
        let (data, response) = try await session.data(from: endpoint.url(path: "api/items"))
        try validate(response, data: data)
        return try decoder.decode([ItemSummary].self, from: data)
    }

    func chat(_ requestBody: ChatRequest) async throws -> ChatResponse {
        try await requestJSON(
            path: "api/chat",
            body: requestBody,
            response: ChatResponse.self,
            headers: ["X-BG3-Companion-Control": companionControlToken]
        )
    }

    func importBuild(_ requestBody: LoadoutImportRequest, idempotencyKey: UUID) async throws -> ImportedBuild {
        let headers = [
            "Idempotency-Key": idempotencyKey.uuidString.lowercased(),
            "X-BG3-Companion-Control": companionControlToken,
        ]
        do {
            return try await requestJSON(
                path: "api/builds/import", body: requestBody,
                response: ImportedBuild.self, timeout: 180, headers: headers
            )
        } catch let error as URLError where Self.retryableTransportErrors.contains(error.code) && !Task.isCancelled {
            return try await requestJSON(
                path: "api/builds/import", body: requestBody,
                response: ImportedBuild.self, timeout: 180, headers: headers
            )
        }
    }

    private static let retryableTransportErrors: Set<URLError.Code> = [
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .networkConnectionLost,
        .notConnectedToInternet,
        .timedOut,
    ]

    func authenticateAppTransaction(_ signedAppTransaction: String) async throws -> CompanionAuthResponse {
        try await requestJSON(
            path: "_companion/session",
            method: "PUT",
            body: AppTransactionAuthRequest(signedAppTransaction: signedAppTransaction),
            response: CompanionAuthResponse.self,
            timeout: 30,
            headers: ["X-BG3-Companion-Control": companionControlToken]
        )
    }

    private func requestJSON<Body: Encodable, Response: Decodable>(
        path: String,
        method: String = "POST",
        body: Body,
        response: Response.Type,
        timeout: TimeInterval = 60,
        headers: [String: String] = [:]
    ) async throws -> Response {
        var request = URLRequest(url: endpoint.url(path: path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try encoder.encode(body)
        let (data, urlResponse) = try await session.data(for: request)
        try validate(urlResponse, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BG3AssistantError.invalidBackendResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(BackendErrorPayload.self, from: data) {
                throw BackendClientError.http(statusCode: http.statusCode, message: payload.detail)
            }
            throw BG3AssistantError.invalidBackendResponse
        }
    }

}

private struct BackendErrorPayload: Decodable {
    let detail: String
}

enum BackendClientError: LocalizedError {
    case http(statusCode: Int, message: String)

    var statusCode: Int {
        switch self {
        case .http(let statusCode, _): statusCode
        }
    }

    var errorDescription: String? {
        switch self {
        case .http(_, let message): message
        }
    }
}
