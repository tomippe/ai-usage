import Foundation

enum CodexUsageClient {
    private static let fetchTimeout: TimeInterval = 15

    static func fetchUsage() -> CodexUsageSnapshot {
        let now = Date()
        guard ProviderAvailability.isCodexInstalled() else {
            return unavailable(now, "not_installed")
        }
        guard let codex = ProviderAvailability.codexBinaryPath() else {
            return unavailable(now, "no_codex_binary")
        }

        let fetched = fetchViaAppServer(codexPath: codex)
        if let snapshot = fetched.snapshot {
            return snapshot
        }
        return unavailable(now, fetched.errorCode ?? "no_rate_limits")
    }

    private static func unavailable(_ fetchedAt: Date, _ code: String) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            weeklyUsedPercent: nil,
            primaryUsedPercent: nil,
            planType: nil,
            weeklyResetsAt: nil,
            primaryResetsAt: nil,
            rateLimitResetCreditsAvailable: nil,
            fetchedAt: fetchedAt,
            errorMessage: code
        )
    }

    private static func fetchViaAppServer(codexPath: String) -> (snapshot: CodexUsageSnapshot?, errorCode: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        let writer = inputPipe.fileHandleForWriting
        let reader = outputPipe.fileHandleForReading

        do {
            try process.run()
        } catch {
            return (nil, "spawn_failed")
        }

        defer {
            writer.closeFile()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  let line = String(data: data, encoding: .utf8) else { return }
            writer.write((line + "\n").data(using: .utf8)!)
        }

        send([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "ai-usage", "version": "0.1.0"],
            ],
        ])

        guard waitForResponse(id: 1, reader: reader, process: process) != nil else {
            return (nil, process.isRunning ? "timeout" : "not_initialized")
        }

        send(["jsonrpc": "2.0", "method": "initialized", "params": [:] as [String: Any]])
        send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": [:] as [String: Any]])

        guard let ratePayload = waitForResponse(id: 2, reader: reader, process: process) else {
            return (nil, "no_rate_limits")
        }

        return parseRateLimits(ratePayload, fetchedAt: Date())
    }

    /// initialize / account/rateLimits/read の id 応答を待つ（通知行は読み飛ばす）。
    private static func waitForResponse(id: Int, reader: FileHandle, process: Process) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(fetchTimeout)
        var buffer = Data()

        while Date() < deadline {
            if !process.isRunning, buffer.isEmpty {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
            } else {
                let chunk = reader.availableData
                if !chunk.isEmpty {
                    buffer.append(chunk)
                } else {
                    Thread.sleep(forTimeInterval: 0.03)
                }
            }

            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newline]
                buffer = buffer[(newline + 1)...]
                guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !line.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                else { continue }

                if let responseId = json["id"] as? Int, responseId == id, json["result"] != nil {
                    return json
                }
                if let responseId = json["id"] as? Int, responseId == id, let err = json["error"] {
                    NSLog("Codex app-server error id=\(id): \(err)")
                    return nil
                }
            }

            if !process.isRunning, buffer.isEmpty { break }
        }
        return nil
    }

    private static func parseRateLimits(_ response: [String: Any], fetchedAt: Date) -> (snapshot: CodexUsageSnapshot?, errorCode: String?) {
        guard let result = response["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any]
        else {
            return (nil, "parse_failed")
        }

        let primary = rateLimits["primary"] as? [String: Any]
        let secondary = rateLimits["secondary"] as? [String: Any]
        let planType = rateLimits["planType"] as? String
        var resetCreditsAvailable: Int?
        if let resetCredits = result["rateLimitResetCredits"] as? [String: Any] {
            resetCreditsAvailable = resetCredits["availableCount"] as? Int
        }

        return (CodexUsageSnapshot(
            weeklyUsedPercent: doubleValue(secondary?["usedPercent"]),
            primaryUsedPercent: doubleValue(primary?["usedPercent"]),
            planType: planType,
            weeklyResetsAt: dateFromUnix(secondary?["resetsAt"]),
            primaryResetsAt: dateFromUnix(primary?["resetsAt"]),
            rateLimitResetCreditsAvailable: resetCreditsAvailable,
            fetchedAt: fetchedAt,
            errorMessage: nil
        ), nil)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String, let n = Double(s) { return n }
        return nil
    }

    private static func dateFromUnix(_ value: Any?) -> Date? {
        guard let seconds = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
