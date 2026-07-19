import Foundation

struct BackendEndpoint: Equatable, Sendable {
    static let infoDictionaryKey = "BG3BackendURL"
    static let managedLocalURL = URL(string: "http://127.0.0.1:8787")!
    static let managedLocal = try! BackendEndpoint(managedLocalURL.absoluteString)

    let baseURL: URL
    let managesLocalBackend: Bool

    init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/" else {
            throw BackendEndpointError.invalidURL
        }

        let isManagedLocal = scheme == "http" && host == "127.0.0.1" && components.port == 8787
        if !isManagedLocal {
            guard scheme == "https", !Self.loopbackHosts.contains(host) else {
                throw BackendEndpointError.remoteEndpointRequiresHTTPS
            }
        }

        components.scheme = scheme
        components.host = host
        components.percentEncodedPath = ""
        guard let normalizedURL = components.url else { throw BackendEndpointError.invalidURL }
        baseURL = normalizedURL
        managesLocalBackend = isManagedLocal
    }

    static var configured: BackendEndpoint {
        do {
            return try configured(
                environment: ProcessInfo.processInfo.environment,
                infoDictionary: Bundle.main.infoDictionary
            )
        } catch {
            fatalError("Invalid backend endpoint configuration: \(error.localizedDescription)")
        }
    }

    static func configured(
        environment: [String: String],
        infoDictionary: [String: Any]?
    ) throws -> BackendEndpoint {
        let configuredValue = environment["BG3_BACKEND_URL"]
            ?? infoDictionary?[infoDictionaryKey] as? String
            ?? managedLocalURL.absoluteString
        return try BackendEndpoint(configuredValue)
    }

    func url(path: String) -> URL {
        baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
}

enum BackendEndpointError: LocalizedError {
    case invalidURL
    case remoteEndpointRequiresHTTPS

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "BG3_BACKEND_URL must be an origin URL without credentials, a path, query, or fragment."
        case .remoteEndpointRequiresHTTPS:
            "Remote BG3_BACKEND_URL values must use HTTPS. Local development must use http://127.0.0.1:8787."
        }
    }
}
