import Foundation

@MainActor
final class BackendProcessManager {
    private var process: Process?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func startIfNeeded() throws {
        if process?.isRunning == true {
            try appendLog("Backend process already running")
            return
        }
        guard let backendDirectory = findBackendDirectory() else {
            try appendLog("Backend directory not found. cwd=\(FileManager.default.currentDirectoryPath) bundle=\(Bundle.main.bundleURL.path)")
            throw BackendProcessError.backendDirectoryNotFound
        }

        let uvPath = findExecutable(named: "uv")
        let pythonPath = backendDirectory.appending(path: ".venv/bin/python").path
        let newProcess = Process()
        newProcess.currentDirectoryURL = backendDirectory

        if let uvPath {
            newProcess.executableURL = URL(fileURLWithPath: uvPath)
            newProcess.arguments = ["run", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8787"]
            try appendLog("Starting backend with uv=\(uvPath) cwd=\(backendDirectory.path)")
        } else if FileManager.default.isExecutableFile(atPath: pythonPath) {
            newProcess.executableURL = URL(fileURLWithPath: pythonPath)
            newProcess.arguments = ["-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8787"]
            try appendLog("Starting backend with python=\(pythonPath) cwd=\(backendDirectory.path)")
        } else {
            try appendLog("No backend runner found. pythonPath=\(pythonPath)")
            throw BackendProcessError.uvNotFound
        }

        let logDirectory = try logDirectory()
        let stdout = try writableLogHandle(at: logDirectory.appending(path: "backend.stdout.log"))
        let stderr = try writableLogHandle(at: logDirectory.appending(path: "backend.stderr.log"))
        newProcess.standardOutput = stdout
        newProcess.standardError = stderr
        try newProcess.run()
        process = newProcess
        try appendLog("Backend process started pid=\(newProcess.processIdentifier)")
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
        let directory = base.appending(path: "CivCoach/debug", directoryHint: .isDirectory)
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
            return "Could not find the CivCoach backend directory from this app launch path."
        case .uvNotFound:
            return "Could not start backend because uv was not found and backend/.venv/bin/python does not exist."
        }
    }
}
