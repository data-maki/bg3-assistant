import Foundation

struct GuideBundle: Decodable {
    let guideVersion: String
    let payloads: [String: RoutePayload]
    let items: [ItemSummary]
}

struct GuideRepository {
    private let bundle: GuideBundle

    init(bundle: Bundle = .main) throws {
        let sourceDataDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Data", directoryHint: .isDirectory)
        let candidates = [
            bundle.resourceURL?.appending(path: "Data/guide-bundle.json"),
            bundle.resourceURL?.appending(path: "guide-bundle.json"),
            sourceDataDirectory.appending(path: "guide-bundle.json"),
        ].compactMap { $0 }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw GuideRepositoryError.resourceMissing
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.bundle = try decoder.decode(GuideBundle.self, from: Data(contentsOf: url))
    }

    var guideVersion: String { bundle.guideVersion }
    var items: [ItemSummary] { bundle.items }

    func payload(for act: Int) throws -> RoutePayload {
        guard let payload = bundle.payloads[String(act)] else {
            throw GuideRepositoryError.unknownAct(act)
        }
        return payload
    }
}

enum GuideRepositoryError: LocalizedError {
    case resourceMissing
    case unknownAct(Int)

    var errorDescription: String? {
        switch self {
        case .resourceMissing: "The bundled guide resource is missing."
        case .unknownAct(let act): "The bundled guide does not contain Act \(act)."
        }
    }
}
