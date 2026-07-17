import Darwin
import Foundation

@MainActor
final class BackendProcessManager {
    private var process: Process?

    var isRunning: Bool {
        process?.isRunning == true
    }

    /// A force-quit or replaced app can leave either the frozen backend or a
    /// development uvicorn listener alive after its GUI owner disappears.
    /// A valid service identity makes either kind safe to replace.
    func retireUnownedBackend(_ health: BackendHealth) async {
        guard process?.isRunning != true else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard health.ok,
              health.service == "bg3-honor-assistant",
              health.parentPid != currentPID,
              let candidate = health.pid ?? listenerProcessIDs().first,
              candidate > 1,
              candidate != currentPID else { return }
        try? appendLog("Retiring unowned backend pid=\(candidate) parent=\(health.parentPid.map(String.init) ?? "legacy") packaged=\(health.packaged.map(String.init) ?? "legacy")")
        _ = Darwin.kill(candidate, SIGTERM)
        for _ in 0..<20 {
            if Darwin.kill(candidate, 0) != 0 { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if Darwin.kill(candidate, 0) == 0 { _ = Darwin.kill(candidate, SIGKILL) }
    }

    nonisolated static func processIDs(from output: String, excluding currentPID: Int32) -> [Int32] {
        output.split(whereSeparator: \.isWhitespace)
            .compactMap { Int32($0) }
            .filter { $0 > 1 && $0 != currentPID }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
    }

    func startIfNeeded(openRouterAPIKey: String? = nil) throws {
        if process?.isRunning == true {
            try appendLog("Backend process already running")
            return
        }
        let newProcess = Process()
        if let bundledBackend = bundledBackendExecutable() {
            newProcess.executableURL = bundledBackend
            newProcess.currentDirectoryURL = bundledBackend.deletingLastPathComponent()
            newProcess.arguments = []
            try appendLog("Starting bundled backend=\(bundledBackend.path)")
        } else {
            guard let backendDirectory = findBackendDirectory() else {
                try appendLog("Backend directory not found. cwd=\(FileManager.default.currentDirectoryPath) bundle=\(Bundle.main.bundleURL.path)")
                throw BackendProcessError.backendDirectoryNotFound
            }
            let uvPath = findExecutable(named: "uv")
            let pythonPath = backendDirectory.appending(path: ".venv/bin/python").path
            newProcess.currentDirectoryURL = backendDirectory
            if FileManager.default.isExecutableFile(atPath: pythonPath) {
                newProcess.executableURL = URL(fileURLWithPath: pythonPath)
                newProcess.arguments = ["-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8787"]
                try appendLog("Starting backend with python=\(pythonPath) cwd=\(backendDirectory.path)")
            } else if let uvPath {
                newProcess.executableURL = URL(fileURLWithPath: uvPath)
                newProcess.arguments = ["run", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8787"]
                try appendLog("Starting backend with uv=\(uvPath) cwd=\(backendDirectory.path)")
            } else {
                try appendLog("No backend runner found. pythonPath=\(pythonPath)")
                throw BackendProcessError.uvNotFound
            }
        }

        let logDirectory = try logDirectory()
        let stdout = try writableLogHandle(at: logDirectory.appending(path: "backend.stdout.log"))
        let stderr = try writableLogHandle(at: logDirectory.appending(path: "backend.stderr.log"))
        var environment = ProcessInfo.processInfo.environment
        if let openRouterAPIKey, !openRouterAPIKey.isEmpty {
            environment["OPENROUTER_API_KEY"] = openRouterAPIKey
        }
        environment["BG3_STATE_DB_PATH"] = RunStore().databaseURL.path
        if let stateRoot = environment["BG3_ASSISTANT_STATE_DIR"], !stateRoot.isEmpty {
            environment["RUNS_DIR"] = URL(fileURLWithPath: stateRoot)
                .appending(path: "backend-runs", directoryHint: .isDirectory)
                .path
        }
        newProcess.environment = environment
        newProcess.standardOutput = stdout
        newProcess.standardError = stderr
        try newProcess.run()
        process = newProcess
        try appendLog("Backend process started pid=\(newProcess.processIdentifier)")
    }

    private func bundledBackendExecutable() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidate = resources.appending(path: "backend/bg3-honor-backend")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private func listenerProcessIDs() -> [Int32] {
        let probe = Process()
        let stdout = Pipe()
        probe.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        probe.arguments = ["-nP", "-tiTCP:8787", "-sTCP:LISTEN"]
        probe.standardOutput = stdout
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
            probe.waitUntilExit()
            let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return Self.processIDs(from: output, excluding: ProcessInfo.processInfo.processIdentifier)
        } catch {
            try? appendLog("Could not inspect port 8787 listener: \(error.localizedDescription)")
            return []
        }
    }

    private func findBackendDirectory() -> URL? {
        var candidates: [URL] = []
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appending(path: "../backend").standardizedFileURL)
        candidates.append(cwd.appending(path: "backend").standardizedFileURL)

        var cursor = Bundle.main.bundleURL
        for _ in 0..<8 {
            candidates.append(cursor.appending(path: "backend").standardizedFileURL)
            candidates.append(cursor.appending(path: "../backend").standardizedFileURL)
            cursor.deleteLastPathComponent()
        }

        return candidates.first { candidate in
            FileManager.default.fileExists(atPath: candidate.appending(path: "pyproject.toml").path)
        }
    }

    private func findExecutable(named name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func logDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "BG3HonorAssistant/debug", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writableLogHandle(at path: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        return handle
    }

    private func appendLog(_ message: String) throws {
        let path = try logDirectory().appending(path: "backend-manager.log")
        let line = "\(Date()) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path.path) {
                let handle = try FileHandle(forWritingTo: path)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: path)
            }
        }
    }
}

enum BackendProcessError: LocalizedError {
    case backendDirectoryNotFound
    case uvNotFound

    var errorDescription: String? {
        switch self {
        case .backendDirectoryNotFound:
            return "Could not find the BG3 Honor Mode Assistant backend directory from this app launch path."
        case .uvNotFound:
            return "Could not start backend because uv was not found and backend/.venv/bin/python does not exist."
        }
    }
}
