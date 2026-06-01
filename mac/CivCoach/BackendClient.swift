import Foundation

struct BackendContext: Encodable {
    let app: String
    let gameDetected: Bool
    let gameName: String
    let screenshotWidth: Int
    let screenshotHeight: Int
    var mode: String = "ask"
    var skipTTS: Bool = false
    var gameLogId: String?
    var previousObservation: ObservationContext?
}

struct Resources: Codable {
    let gold: String
    let science: String
    let culture: String
    let influence: String
    let happiness: String
}

struct DetectedFields: Codable {
    let game: String
    let leader: String
    let civilization: String
    let age: String
    let yearOrTurn: String
    let citiesVisible: [String]
    let selectedUnitOrPanel: String
    let resources: Resources
    let currentProblemOrPrompt: String
}

struct ObservationContext: Codable {
    let turnNumber: String
    let year: String
    let screenSummary: String
    let actionCandidate: String
    let resources: Resources
    let selectedUnitOrPanel: String
    let currentProblemOrPrompt: String
}

struct TurnObservation: Codable {
    let turnNumber: String
    let year: String
    let phaseOrPrompt: String
    let actionCandidate: String
    let actionKind: String
    let actionConfidence: Double
    let importantValues: [String]
    let changedSincePrevious: [String]
}

struct Confidence: Codable {
    let overall: Double
    let leader: Double
    let yearOrTurn: Double
    let citiesVisible: Double
}

struct AnalysisResponse: Codable {
    let ok: Bool
    let analysisId: String
    let spokenText: String
    let screenSummary: String
    let detected: DetectedFields
    let observation: TurnObservation
    let confidence: Confidence
    let audioBase64: String
    let latencyMs: Int
    let error: String?
    let audioError: String?
}

struct BackendClient {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!

    func health() async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "health"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let decoder = JSONDecoder()
            return (try decoder.decode(HealthResponse.self, from: data)).ok
        } catch {
            return false
        }
    }

    func analyze(imageData: Data, context: BackendContext) async throws -> AnalysisResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "analyze"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(imageData: imageData, context: context, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CivCoachError.invalidBackendResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AnalysisResponse.self, from: data)
    }

    private func multipartBody(imageData: Data, context: BackendContext, boundary: String) throws -> Data {
        var body = Data()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let contextData = try encoder.encode(context)
        let contextString = String(decoding: contextData, as: UTF8.self)

        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"context\"\r\n\r\n", to: &body)
        append("\(contextString)\r\n", to: &body)

        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"image\"; filename=\"screenshot.jpg\"\r\n", to: &body)
        append("Content-Type: image/jpeg\r\n\r\n", to: &body)
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n", to: &body)
        return body
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }
}

private struct HealthResponse: Decodable {
    let ok: Bool
}
