import Foundation

struct BackendContext: Encodable {
    let gameDetected: Bool
    let gameName: String
    let checkpointId: String?
    let party: [PartyMember]
    let screenshotWidth: Int
    let screenshotHeight: Int
}

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
        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return (try decoder.decode(HealthResponse.self, from: data)).ok
        } catch { return false }
    }

    func route() async throws -> RoutePayload {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "api/act1/route"))
        try validate(response)
        return try decoder.decode(RoutePayload.self, from: data)
    }

    func readiness(_ requestBody: ReadinessRequest) async throws -> ReadinessResponse {
        try await postJSON(path: "api/act1/readiness", body: requestBody, response: ReadinessResponse.self)
    }

    func chat(_ requestBody: ChatRequest) async throws -> ChatResponse {
        try await postJSON(path: "api/chat", body: requestBody, response: ChatResponse.self)
    }

    func analyze(imageData: Data, context: BackendContext) async throws -> AnalysisResponse {
        try await postMultipart(path: "analyze", imageData: imageData, context: context, response: AnalysisResponse.self)
    }

    func alignMap(imageData: Data, context: MapAlignContext) async throws -> MapAlignResponse {
        try await postMultipart(path: "api/map-align", imageData: imageData, context: context, response: MapAlignResponse.self)
    }

    private func postMultipart<Context: Encodable, Response: Decodable>(
        path: String, imageData: Data, context: Context, response: Response.Type
    ) async throws -> Response {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(imageData: imageData, context: context, boundary: boundary)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        try validate(urlResponse)
        return try decoder.decode(Response.self, from: data)
    }

    private func postJSON<Body: Encodable, Response: Decodable>(path: String, body: Body, response: Response.Type) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        try validate(urlResponse)
        return try decoder.decode(Response.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BG3AssistantError.invalidBackendResponse
        }
    }

    private func multipartBody<Context: Encodable>(imageData: Data, context: Context, boundary: String) throws -> Data {
        var body = Data()
        let contextString = String(decoding: try encoder.encode(context), as: UTF8.self)
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"context\"\r\n\r\n\(contextString)\r\n", to: &body)
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"screenshot.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n", to: &body)
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n", to: &body)
        return body
    }

    private func append(_ string: String, to data: inout Data) { data.append(Data(string.utf8)) }
}

private struct HealthResponse: Decodable { let ok: Bool }
