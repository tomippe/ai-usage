import Foundation

enum ClaudeUsageClient {
    private static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    private static var snapshotURL: URL {
        claudeDirectory.appendingPathComponent("ai-usage-rate-limits.json")
    }

    /// Called as Claude Code's statusline command. Keep only quota fields; session paths and prompt data are discarded.
    static func consumeStatusLineInput() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
            let limits = root["rate_limits"] as? [String: Any]
        else { return }

        var output: [String: Any] = ["fetchedAt": Date().timeIntervalSince1970]
        for name in ["five_hour", "seven_day"] {
            guard let window = limits[name] as? [String: Any] else { continue }
            if let percent = window["used_percentage"] as? NSNumber {
                output["\(name)UsedPercent"] = percent
            }
            if let reset = window["resets_at"] as? NSNumber {
                output["\(name)ResetsAt"] = reset
            }
        }
        guard output.count > 1,
              let data = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]) else { return }
        do {
            try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            return
        }

        let five = (output["five_hourUsedPercent"] as? NSNumber).map { formatPercent(remainingPercent(fromUsed: $0.doubleValue)) }
        let seven = (output["seven_dayUsedPercent"] as? NSNumber).map { formatPercent(remainingPercent(fromUsed: $0.doubleValue)) }
        var labels: [String] = []
        if let five { labels.append("5h \(five)") }
        if let seven { labels.append("7d \(seven)") }
        if !labels.isEmpty { print("AI Usage · " + labels.joined(separator: " / ")) }
    }

    /// Adds the statusline only when the user has not configured one. Existing custom statuslines are preserved.
    static func installStatusLineIfAvailable(executablePath: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let hasClaudeCodeState = FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude.json").path)
            || FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent(".credentials.json").path)
        guard hasClaudeCodeState else { return }

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        }
        guard settings["statusLine"] == nil else { return }

        settings["statusLine"] = [
            "type": "command",
            "command": "\"\(executablePath.replacingOccurrences(of: "\"", with: "\\\""))\" --claude-statusline",
            "refreshInterval": 30,
        ]
        do {
            try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            NSLog("AI Usage could not register the Claude Code statusline: %@", error.localizedDescription)
        }
    }

    static func readSnapshot() -> ClaudeUsageSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        return ClaudeUsageSnapshot(
            fiveHourUsedPercent: number("five_hourUsedPercent"),
            sevenDayUsedPercent: number("seven_dayUsedPercent"),
            fiveHourResetsAt: number("five_hourResetsAt").map(Date.init(timeIntervalSince1970:)),
            sevenDayResetsAt: number("seven_dayResetsAt").map(Date.init(timeIntervalSince1970:)),
            fetchedAt: Date(timeIntervalSince1970: number("fetchedAt") ?? 0)
        )
    }
}
