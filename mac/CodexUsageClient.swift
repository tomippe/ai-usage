import Foundation

enum CodexUsageClient {
    private static let fetchTimeout: TimeInterval = 15

    static func fetchUsage() -> CodexUsageSnapshot {
        let now = Date()
        guard ProviderAvailability.isCodexInstalled() else {
            return CodexUsageSnapshot(
                weeklyUsedPercent: nil, primaryUsedPercent: nil, planType: nil,
                weeklyResetsAt: nil, primaryResetsAt: nil, fetchedAt: now,
                errorMessage: "not_installed"
            )
        }
        guard let codex = ProviderAvailability.codexBinaryPath() else {
            return CodexUsageSnapshot(
                weeklyUsedPercent: nil, primaryUsedPercent: nil, planType: nil,
                weeklyResetsAt: nil, primaryResetsAt: nil, fetchedAt: now,
                errorMessage: "no_codex_binary"
            )
        }

        let lines = runAppServer(codexPath: codex)
        guard let rateLine = lines.first(where: { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["id"] as? Int == 2,
                  json["result"] != nil else { return false }
            return true
        }) else {
            return CodexUsageSnapshot(
                weeklyUsedPercent: nil, primaryUsedPercent: nil, planType: nil,
                weeklyResetsAt: nil, primaryResetsAt: nil, fetchedAt: now,
                errorMessage: "no_rate_limits"
            )
        }

        guard let data = rateLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any]
        else {
            return CodexUsageSnapshot(
                weeklyUsedPercent: nil, primaryUsedPercent: nil, planType: nil,
                weeklyResetsAt: nil, primaryResetsAt: nil, fetchedAt: now,
                errorMessage: "parse_failed"
            )
        }

        let primary = rateLimits["primary"] as? [String: Any]
        let secondary = rateLimits["secondary"] as? [String: Any]
        let planType = rateLimits["planType"] as? String

        return CodexUsageSnapshot(
            weeklyUsedPercent: doubleValue(secondary?["usedPercent"]),
            primaryUsedPercent: doubleValue(primary?["usedPercent"]),
            planType: planType,
            weeklyResetsAt: dateFromUnix(secondary?["resetsAt"]),
            primaryResetsAt: dateFromUnix(primary?["resetsAt"]),
            fetchedAt: now,
            errorMessage: nil
        )
    }

    private static func runAppServer(codexPath: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        let initLine = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"ai-usage","version":"0.1.0"}}}
        """
        let rateLine = """
        {"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}
        """

        do {
            try process.run()
            let payload = initLine + "\n" + rateLine + "\n"
            inputPipe.fileHandleForWriting.write(payload.data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()

            let group = DispatchGroup()
            group.enter()
            var collected = Data()
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                    return
                }
                collected.append(chunk)
            }

            let deadline = DispatchTime.now() + fetchTimeout
            if group.wait(timeout: deadline) == .timedOut {
                process.terminate()
            }
            process.waitUntilExit()

            let text = String(data: collected, encoding: .utf8) ?? ""
            return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        } catch {
            return []
        }
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
