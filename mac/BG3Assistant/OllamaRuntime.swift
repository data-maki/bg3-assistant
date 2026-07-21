import Foundation

final class OllamaRuntime: @unchecked Sendable {
    static let model = "qwen3:4b"
    static let version = "0.30.10"
    static let baseURL = URL(string: "http://127.0.0.1:11435")!

    private let lock = NSLock()
    private var process: Process?

    deinit { stop() }

    func isRunning() async -> Bool {
        var request = URLRequest(url: Self.baseURL.appending(path: "api/version"))
        request.timeoutInterval = 1
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return root["version"] as? String == Self.version
    }

    func isModelInstalled() async throws -> Bool {
        try await ensureRunning()
        let (data, response) = try await URLSession.shared.data(from: Self.baseURL.appending(path: "api/tags"))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { throw AIProviderError.invalidResponse }
        return models.contains { model in
            let name = model["name"] as? String ?? model["model"] as? String
            return name == Self.model
        }
    }

    func ensureReady() async throws {
        guard try await isModelInstalled() else { throw AIProviderError.modelNotInstalled }
    }

    func ensureRunning() async throws {
        if await isRunning() { return }
        try start()
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(250))
            if await isRunning() { return }
        }
        throw AIProviderError.runtimeUnavailable("Ollama did not start.")
    }

    func installModel(progress: @escaping @Sendable (Double?) -> Void) async throws {
        try await ensureRunning()
        var request = URLRequest(url: Self.baseURL.appending(path: "api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": Self.model, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIProviderError.runtimeUnavailable("The model download could not start.")
        }
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = event["error"] as? String { throw AIProviderError.runtimeUnavailable(error) }
            if let total = event["total"] as? Double,
               let completed = event["completed"] as? Double,
               total > 0 {
                progress(min(completed / total, 1))
            } else {
                progress(nil)
            }
        }
        guard try await isModelInstalled() else { throw AIProviderError.modelNotInstalled }
        progress(1)
    }

    func stop() {
        lock.lock()
        let runningProcess = process
        process = nil
        lock.unlock()
        guard let runningProcess, runningProcess.isRunning else { return }
        runningProcess.terminate()
    }

    private func start() throws {
        lock.lock()
        defer { lock.unlock() }
        if process?.isRunning == true { return }
        guard let executableURL else {
            throw AIProviderError.runtimeUnavailable("The bundled Ollama runtime is missing.")
        }
        let modelDirectory = try modelDirectoryURL()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["serve"]
        process.environment = [
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": NSTemporaryDirectory(),
            "OLLAMA_HOST": "127.0.0.1:11435",
            "OLLAMA_MODELS": modelDirectory.path,
            "OLLAMA_NO_CLOUD": "1",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
    }

    private var executableURL: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "ollama/bin/ollama"),
            Bundle.main.resourceURL?.appending(path: "ollama/ollama"),
            URL(fileURLWithPath: "/usr/local/bin/ollama"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ollama"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func modelDirectoryURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "BG3HonorAssistant/OllamaModels", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
