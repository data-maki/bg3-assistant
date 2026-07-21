import Foundation

struct ImportedBuildStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = support.appending(path: "BG3HonorAssistant", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "imported-builds.json")
    }

    func load() -> [BuildSummary] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([BuildSummary].self, from: data)) ?? []
    }

    func save(_ builds: [BuildSummary]) throws {
        let data = try JSONEncoder().encode(builds)
        try data.write(to: fileURL, options: .atomic)
    }
}
