import Foundation

struct Logger {
    func saveScreenshot(_ data: Data) throws -> URL {
        let directory = try debugDirectory()
        let path = directory.appending(path: "latest_screenshot.jpg")
        try data.write(to: path, options: .atomic)
        return path
    }

    func saveResponse(_ response: AnalysisResponse) throws {
        let directory = try debugDirectory()
        let path = directory.appending(path: "latest_response.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)
        try data.write(to: path, options: .atomic)
    }

    private func debugDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "CivCoach/debug", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
