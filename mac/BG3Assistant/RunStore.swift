import Foundation

struct RunStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "BG3HonorAssistant", directoryHint: .isDirectory)
    }

    func load() -> HonorRun {
        guard let data = try? Data(contentsOf: runURL), let run = try? decoder.decode(HonorRun.self, from: data) else {
            return HonorRun()
        }
        return run
    }

    func save(_ run: HonorRun) throws {
        let directory = runURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archiveDirectory = directory.appending(path: "runs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(run)
        try data.write(to: runURL, options: .atomic)
        try data.write(to: archiveDirectory.appending(path: "\(run.id).json"), options: .atomic)
    }

    var runURL: URL {
        baseDirectory.appending(path: "run.json")
    }
}
