import Foundation
import Security

enum ClaudeUsageClient {
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let keychainServices = ["Claude Code-credentials", "claude-code-credentials"]
    private static let credentialsFileName = ".credentials.json"
    private static let fetchTimeout: TimeInterval = 15
    private static let refreshLeadTime: TimeInterval = 120
    private static let refreshQueue = DispatchQueue(label: "jp.tomippe.ai-usage.claude-oauth-refresh")
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
            fetchedAt: Date(timeIntervalSince1970: number("fetchedAt") ?? 0),
            errorMessage: nil
        )
    }

    static func hasOAuthCredentials() -> Bool {
        loadCredentialsRoot() != nil
    }

    /// Polls the OAuth usage endpoint (Claude Code login). Statusline JSON is merged separately.
    static func fetchOAuthUsage() -> ClaudeUsageSnapshot {
        let now = Date()
        guard hasOAuthCredentials() else {
            return oauthUnavailable(now, "no_credentials")
        }
        guard var root = loadCredentialsRoot(), var oauth = oauthDict(from: root) else {
            return oauthUnavailable(now, "no_credentials")
        }
        guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
            return oauthUnavailable(now, "not_logged_in")
        }

        var accessToken = (ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if accessToken.isEmpty {
            accessToken = oauth["accessToken"] as? String ?? ""
        }
        if accessToken.isEmpty {
            return oauthUnavailable(now, "not_logged_in")
        }

        if shouldRefreshAccessToken(oauth: oauth, now: now), ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"] == nil {
            switch refreshAccessToken(refreshToken: refreshToken, root: root) {
            case .success(let updated):
                root = updated.root
                oauth = updated.oauth
                accessToken = updated.accessToken
            case .failure("refresh_rate_limited"):
                break
            case .failure(let code):
                return oauthUnavailable(now, code)
            }
        }

        switch fetchUsage(accessToken: accessToken) {
        case .success(let snap):
            return snap
        case .failure(.code("unauthorized")):
            switch refreshAccessToken(refreshToken: refreshToken, root: root) {
            case .success(let updated):
                switch fetchUsage(accessToken: updated.accessToken) {
                case .success(let snap):
                    return snap
                case .failure(.code(let retryCode)):
                    return oauthUnavailable(now, retryCode)
                }
            case .failure(let refreshCode):
                return oauthUnavailable(now, refreshCode)
            }
        case .failure(.code(let code)):
            return oauthUnavailable(now, code)
        }
    }

    /// Prefer newer `fetchedAt` per field; on rate-limit errors keep prior usage when possible.
    static func mergeSources(
        oauth: ClaudeUsageSnapshot?,
        statusline: ClaudeUsageSnapshot?,
        retaining previous: ClaudeUsageSnapshot?
    ) -> ClaudeUsageSnapshot? {
        let oauthSide = oauth ?? previous.map(stripError)
        let combined = combineSnapshots(oauthSide, statusline)
        if let combined, combined.hasMenuUsage {
            return combined
        }
        if let prev = previous, prev.hasMenuUsage,
           let err = oauth?.errorMessage,
           ["rate_limited", "refresh_rate_limited", "network"].contains(err) {
            return combineSnapshots(prev, statusline) ?? prev
        }
        return combined ?? previous
    }

    private static func stripError(_ snap: ClaudeUsageSnapshot) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fiveHourUsedPercent: snap.fiveHourUsedPercent,
            sevenDayUsedPercent: snap.sevenDayUsedPercent,
            fiveHourResetsAt: snap.fiveHourResetsAt,
            sevenDayResetsAt: snap.sevenDayResetsAt,
            fetchedAt: snap.fetchedAt,
            errorMessage: nil
        )
    }

    private static func combineSnapshots(_ a: ClaudeUsageSnapshot?, _ b: ClaudeUsageSnapshot?) -> ClaudeUsageSnapshot? {
        guard let a else { return b }
        guard let b else { return a }
        let newer = a.fetchedAt >= b.fetchedAt ? a : b
        let older = a.fetchedAt >= b.fetchedAt ? b : a
        return ClaudeUsageSnapshot(
            fiveHourUsedPercent: newer.fiveHourUsedPercent ?? older.fiveHourUsedPercent,
            sevenDayUsedPercent: newer.sevenDayUsedPercent ?? older.sevenDayUsedPercent,
            fiveHourResetsAt: newer.fiveHourResetsAt ?? older.fiveHourResetsAt,
            sevenDayResetsAt: newer.sevenDayResetsAt ?? older.sevenDayResetsAt,
            fetchedAt: max(a.fetchedAt, b.fetchedAt),
            errorMessage: newer.errorMessage ?? older.errorMessage
        )
    }

    private static func oauthUnavailable(_ fetchedAt: Date, _ code: String) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fiveHourUsedPercent: nil,
            sevenDayUsedPercent: nil,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
            fetchedAt: fetchedAt,
            errorMessage: code
        )
    }

    private static func oauthUserAgent() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return "claude-code/\(version)"
    }

    private struct StoredOAuth {
        var root: [String: Any]
        var oauth: [String: Any]
        var accessToken: String
        var keychainService: String?
        var keychainAccount: String?
    }

    private static func loadCredentialsRoot() -> [String: Any]? {
        if let fromKeychain = loadCredentialsFromKeychain() {
            return fromKeychain.root
        }
        let fileURL = claudeDirectory.appendingPathComponent(credentialsFileName)
        guard let data = try? Data(contentsOf: fileURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root
    }

    private static func loadCredentialsFromKeychain() -> StoredOAuth? {
        for service in keychainServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let dict = item as? [String: Any],
                  let data = dict[kSecValueData as String] as? Data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = oauthDict(from: json),
                  let access = oauth["accessToken"] as? String else { continue }
            let account = dict[kSecAttrAccount as String] as? String
            return StoredOAuth(root: json, oauth: oauth, accessToken: access, keychainService: service, keychainAccount: account)
        }
        return nil
    }

    private static func oauthDict(from root: [String: Any]) -> [String: Any]? {
        root["claudeAiOauth"] as? [String: Any]
    }

    private static func shouldRefreshAccessToken(oauth: [String: Any], now: Date) -> Bool {
        guard let expiresAt = oauth["expiresAt"] else { return true }
        let ms: Double
        if let n = expiresAt as? NSNumber {
            ms = n.doubleValue
        } else if let i = expiresAt as? Int {
            ms = Double(i)
        } else {
            return true
        }
        let expiry = Date(timeIntervalSince1970: ms / 1000)
        return now.addingTimeInterval(refreshLeadTime) >= expiry
    }

    private enum RefreshResult {
        case success(StoredOAuth)
        case failure(String)
    }

    private static func refreshAccessToken(refreshToken: String, root: [String: Any]) -> RefreshResult {
        var result: RefreshResult = .failure("refresh_failed")
        refreshQueue.sync {
            result = refreshAccessTokenUnlocked(refreshToken: refreshToken, root: root)
        }
        return result
    }

    private static func refreshAccessTokenUnlocked(refreshToken: String, root: [String: Any]) -> RefreshResult {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure("refresh_failed")
        }
        var request = URLRequest(url: tokenURL, timeoutInterval: fetchTimeout)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(oauthUserAgent(), forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try URLSession.shared.synchronize(request: request)
        } catch {
            return .failure("network")
        }
        guard let http = response as? HTTPURLResponse else { return .failure("network") }
        if http.statusCode == 429 { return .failure("refresh_rate_limited") }
        guard http.statusCode == 200,
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = parsed["access_token"] as? String, !access.isEmpty else {
            if http.statusCode == 401 || http.statusCode == 403 { return .failure("not_logged_in") }
            return .failure("refresh_failed")
        }

        var oauth = oauthDict(from: root) ?? [:]
        oauth["accessToken"] = access
        if let rotated = parsed["refresh_token"] as? String, !rotated.isEmpty {
            oauth["refreshToken"] = rotated
        }
        if let expiresIn = (parsed["expires_in"] as? NSNumber)?.doubleValue ?? (parsed["expires_in"] as? Int).map(Double.init) {
            oauth["expiresAt"] = Int64(Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000)
        }
        var updatedRoot = root
        updatedRoot["claudeAiOauth"] = oauth
        persistCredentialsRoot(updatedRoot)
        return .success(StoredOAuth(root: updatedRoot, oauth: oauth, accessToken: access, keychainService: nil, keychainAccount: nil))
    }

    private static func persistCredentialsRoot(_ root: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return }
        let fileURL = claudeDirectory.appendingPathComponent(credentialsFileName)
        try? FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)

        guard let oauth = oauthDict(from: root) else { return }
        for service in keychainServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let dict = item as? [String: Any],
                  let account = dict[kSecAttrAccount as String] as? String else { continue }
            var updateRoot = root
            updateRoot["claudeAiOauth"] = oauth
            guard let keychainData = try? JSONSerialization.data(withJSONObject: updateRoot, options: [.sortedKeys]) else { continue }
            let update: [String: Any] = [kSecValueData as String: keychainData]
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemUpdate(updateQuery as CFDictionary, update as CFDictionary)
            break
        }
    }

    private enum OAuthFetchFailure: Error {
        case code(String)
    }

    private static func fetchUsage(accessToken: String) -> Result<ClaudeUsageSnapshot, OAuthFetchFailure> {
        var request = URLRequest(url: usageURL, timeoutInterval: fetchTimeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(oauthUserAgent(), forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try URLSession.shared.synchronize(request: request)
        } catch {
            return .failure(.code("network"))
        }
        guard let http = response as? HTTPURLResponse else { return .failure(.code("network")) }
        if http.statusCode == 429 { return .failure(.code("rate_limited")) }
        if http.statusCode == 401 { return .failure(.code("unauthorized")) }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.code("usage_failed"))
        }
        return .success(parseUsageResponse(json, fetchedAt: Date()))
    }

    private static func parseUsageResponse(_ json: [String: Any], fetchedAt: Date) -> ClaudeUsageSnapshot {
        func window(_ key: String) -> (Double?, Date?) {
            guard let w = json[key] as? [String: Any] else { return (nil, nil) }
            let util = (w["utilization"] as? NSNumber)?.doubleValue
            let reset = parseResetsAt(w["resets_at"])
            return (util, reset)
        }
        let five = window("five_hour")
        let seven = window("seven_day")
        return ClaudeUsageSnapshot(
            fiveHourUsedPercent: five.0,
            sevenDayUsedPercent: seven.0,
            fiveHourResetsAt: five.1,
            sevenDayResetsAt: seven.1,
            fetchedAt: fetchedAt,
            errorMessage: nil
        )
    }

    private static func parseResetsAt(_ value: Any?) -> Date? {
        switch value {
        case let n as NSNumber:
            return Date(timeIntervalSince1970: n.doubleValue)
        case let i as Int:
            return Date(timeIntervalSince1970: Double(i))
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if let secs = Double(trimmed) { return Date(timeIntervalSince1970: secs) }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: trimmed) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: trimmed)
        default:
            return nil
        }
    }
}

private extension URLSession {
    func synchronize(request: URLRequest) throws -> (Data, URLResponse) {
        var pair: (Data, URLResponse)?
        var err: Error?
        let group = DispatchGroup()
        group.enter()
        let task = dataTask(with: request) { data, response, error in
            if let error {
                err = error
            } else if let data, let response {
                pair = (data, response)
            }
            group.leave()
        }
        task.resume()
        group.wait()
        if let err { throw err }
        guard let pair else { throw URLError(.badServerResponse) }
        return pair
    }
}
