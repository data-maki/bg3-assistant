import Foundation

struct GameLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let turnNumber: String
    let year: String
    let action: String
    let actionKind: String
    let confidence: Double
    let summary: String
    let importantValues: [String]
    let changedValues: [String]
}

@MainActor
final class GameLogManager {
    private(set) var gameId: String = ""
    private(set) var logURL: URL?
    private var lastTurnKey = ""

    func startNewGameLog(initialDetection: String) throws -> URL {
        gameId = Self.makeGameId()
        lastTurnKey = ""
        let directory = try Self.logDirectory()
        let url = directory.appending(path: "\(gameId).md")
        let header = """
        # CivCoach Game Log

        - Game ID: \(gameId)
        - Started: \(Self.timestamp(Date()))
        - Initial detection: \(initialDetection)

        ## Important Values To Record First

        - Turn number
        - Year/date
        - Age
        - Leader
        - Civilization
        - Visible cities
        - Selected unit or open panel
        - Current decision prompt
        - Resources: gold, science, culture, influence, happiness
        - Alerts and progress indicators
        - Visible map situation
        - Conservative player action candidate

        """
        try header.write(to: url, atomically: true, encoding: .utf8)
        logURL = url
        return url
    }

    func append(_ entry: GameLogEntry) throws {
        guard let logURL else {
            throw GameLogError.noActiveLog
        }

        let turnKey = stableTurnKey(turn: entry.turnNumber, year: entry.year)
        var markdown = ""
        if turnKey != lastTurnKey {
            markdown += "\n## Turn \(entry.turnNumber.isEmpty ? "unknown" : entry.turnNumber)"
            if !entry.year.isEmpty, entry.year != "unknown" {
                markdown += " - \(entry.year)"
            }
            markdown += "\n\n"
            lastTurnKey = turnKey
        }

        markdown += "- \(Self.timestamp(entry.timestamp))"
        markdown += " | action: \(entry.action.isEmpty ? "unknown" : entry.action)"
        markdown += " | kind: \(entry.actionKind.isEmpty ? "unknown" : entry.actionKind)"
        markdown += " | confidence: \(String(format: "%.2f", entry.confidence))\n"
        markdown += "  - Summary: \(entry.summary.isEmpty ? "unknown" : entry.summary)\n"
        if !entry.importantValues.isEmpty {
            markdown += "  - Values: \(entry.importantValues.joined(separator: "; "))\n"
        }
        if !entry.changedValues.isEmpty {
            markdown += "  - Changed: \(entry.changedValues.joined(separator: "; "))\n"
        }

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(markdown.utf8))
        try handle.close()
    }

    static func logDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "CivCoach/game-logs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func makeGameId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "civcoach-game-\(formatter.string(from: Date()))"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func stableTurnKey(turn: String, year: String) -> String {
        let turnValue = turn.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearValue = year.trimmingCharacters(in: .whitespacesAndNewlines)
        if !turnValue.isEmpty, turnValue != "unknown" {
            return "turn:\(turnValue)"
        }
        if !yearValue.isEmpty, yearValue != "unknown" {
            return "year:\(yearValue)"
        }
        return "unknown"
    }
}

enum GameLogError: LocalizedError {
    case noActiveLog

    var errorDescription: String? {
        switch self {
        case .noActiveLog:
            return "No active game log. Start recording first."
        }
    }
}
