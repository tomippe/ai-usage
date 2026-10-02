import Foundation
import SQLite3

enum CursorUsageClient {
    private static let fetchTimeout: TimeInterval = 15
    private static var cachedAuth: (info: AuthInfo, ts: Date)?
    private static let authCacheTTL: TimeInterval = 10
    private static var cachedSetup: SetupCache?

    private struct AuthInfo {
        let userId: String
        let sessionToken: String
        let email: String?
        let accessToken: String
    }

    private struct SetupCache {
        let isTeamMember: Bool
        let teamId: Int?
        let maxRequestUsage: Int
        let onDemandEnabled: Bool
        let planName: String?
    }

    static func fetchUsage() -> CursorUsageSnapshot {
        let now = Date()
        guard ProviderAvailability.isCursorInstalled() else {
            return emptySnapshot(at: now, error: "not_installed")
        }
        guard let auth = loadAuth() else {
            return emptySnapshot(at: now, error: "not_logged_in")
        }
        guard let setup = ensureSetup(auth: auth) else {
            return emptySnapshot(at: now, error: "setup_failed")
        }

        if setup.isTeamMember {
            return fetchTeamUsage(auth: auth, setup: setup, now: now)
        }
        return fetchSoloUsage(auth: auth, setup: setup, now: now)
    }

    private static func emptySnapshot(at now: Date, error: String) -> CursorUsageSnapshot {
        CursorUsageSnapshot(
            planName: nil, totalPercentUsed: nil, usedRequests: 0, limitRequests: 0,
            resetsAt: nil, fetchedAt: now, errorMessage: error
        )
    }

    private static func loadAuth() -> AuthInfo? {
        if let cached = cachedAuth, Date().timeIntervalSince(cached.ts) < authCacheTTL {
            return cached.info
        }
        let dbPath = ProviderAvailability.cursorDatabasePath()
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        let jwt = queryString(db: db, key: "cursorAuth/accessToken")
        guard let jwt, !jwt.isEmpty else { return nil }

        guard let userId = parseUserId(fromJWT: jwt) else { return nil }
        let email = queryString(db: db, key: "cursorAuth/cachedEmail")
        let sessionToken = "\(userId)%3A%3A\(jwt)"
        let info = AuthInfo(userId: userId, sessionToken: sessionToken, email: email, accessToken: jwt)
        cachedAuth = (info, Date())
        return info
    }

    private static func queryString(db: OpaquePointer, key: String) -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cStr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cStr)
    }

    private static func parseUserId(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else { return nil }
        if let pipe = sub.split(separator: "|").last {
            return String(pipe)
        }
        return sub
    }

    private static func cursorHeaders(sessionToken: String) -> [String: String] {
        [
            "Content-Type": "application/json",
            "Cookie": "WorkosCursorSessionToken=\(sessionToken)",
            "Origin": "https://cursor.com",
            "Referer": "https://cursor.com/dashboard",
        ]
    }

    private static func ensureSetup(auth: AuthInfo) -> SetupCache? {
        if let cachedSetup { return cachedSetup }
        let headers = cursorHeaders(sessionToken: auth.sessionToken)
        guard let stripeData = httpGET(url: "https://cursor.com/api/auth/stripe", headers: headers),
              let usageData = httpGET(url: "https://cursor.com/api/usage?user=\(auth.userId)", headers: headers)
        else { return nil }

        let totals = extractUsageTotals(usageData)
        let planName = formatPlanName(
            (stripeData["individualMembershipType"] as? String)
                ?? (stripeData["membershipType"] as? String)
                ?? (stripeData["teamMembershipType"] as? String)
        )
        let isTeam = (stripeData["isTeamMember"] as? Bool) == true
        let teamId = stripeData["teamId"] as? Int
        let onDemand = (stripeData["isOnBillableAuto"] as? Bool) == true
        let maxReq = totals.limit > 0 ? totals.limit : max(totals.used, 0)

        let setup = SetupCache(
            isTeamMember: isTeam && teamId != nil,
            teamId: teamId,
            maxRequestUsage: maxReq,
            onDemandEnabled: onDemand,
            planName: planName
        )
        cachedSetup = setup
        return setup
    }

    private static func fetchSoloUsage(auth: AuthInfo, setup: SetupCache, now: Date) -> CursorUsageSnapshot {
        let headers = cursorHeaders(sessionToken: auth.sessionToken)
        guard let usage = httpGET(url: "https://cursor.com/api/usage?user=\(auth.userId)", headers: headers) else {
            return emptySnapshot(at: now, error: "usage_failed")
        }
        let totals = extractUsageTotals(usage)
        var resetsAt: Date?
        if let start = usage["startOfMonth"] as? String {
            resetsAt = nextMonth(fromISO: start)
        }

        var snapshot = CursorUsageSnapshot(
            planName: setup.planName,
            totalPercentUsed: nil,
            usedRequests: totals.used,
            limitRequests: totals.limit,
            resetsAt: resetsAt,
            fetchedAt: now,
            errorMessage: nil
        )
        if let period = fetchCurrentPeriodUsage(accessToken: auth.accessToken) {
            if let pct = period.totalPercentUsed { snapshot.totalPercentUsed = pct }
            if let end = period.billingCycleEndMs {
                snapshot.resetsAt = Date(timeIntervalSince1970: end / 1000)
            }
        }
        return snapshot
    }

    private static func fetchTeamUsage(auth: AuthInfo, setup: SetupCache, now: Date) -> CursorUsageSnapshot {
        let headers = cursorHeaders(sessionToken: auth.sessionToken)
        guard let teamId = setup.teamId,
              let teamData = httpPOST(
                url: "https://cursor.com/api/dashboard/get-team-spend",
                headers: headers,
                body: ["teamId": teamId]
              )
        else {
            return emptySnapshot(at: now, error: "team_failed")
        }

        var usageTotals: (used: Int, limit: Int)?
        if let usage = httpGET(url: "https://cursor.com/api/usage?user=\(auth.userId)", headers: headers) {
            usageTotals = extractUsageTotals(usage)
        }

        let members = teamData["teamMemberSpend"] as? [[String: Any]] ?? []
        let me = members.first { member in
            (member["email"] as? String) == auth.email || String(describing: member["userId"] ?? "") == auth.userId
        }
        guard let me else { return emptySnapshot(at: now, error: "team_member_missing") }

        let memberUsed = intValue(me["includedRequestsUsed"]) ?? intValue(me["numRequests"]) ?? 0
        let memberLimit = intValue(me["includedRequestLimit"]) ?? intValue(me["maxRequestUsage"]) ?? setup.maxRequestUsage
        let used = (usageTotals?.used ?? 0) > 0 ? usageTotals!.used : memberUsed
        let limit = (usageTotals?.limit ?? 0) > 0 ? usageTotals!.limit : memberLimit

        var resetsAt: Date?
        if let ms = doubleValue(teamData["nextCycleStart"]) {
            resetsAt = Date(timeIntervalSince1970: ms / 1000)
        }

        var snapshot = CursorUsageSnapshot(
            planName: setup.planName,
            totalPercentUsed: nil,
            usedRequests: used,
            limitRequests: limit,
            resetsAt: resetsAt,
            fetchedAt: now,
            errorMessage: nil
        )
        if let period = fetchCurrentPeriodUsage(accessToken: auth.accessToken) {
            if let pct = period.totalPercentUsed { snapshot.totalPercentUsed = pct }
        }
        return snapshot
    }

    private struct PeriodUsage {
        var totalPercentUsed: Double?
        var billingCycleEndMs: Double?
    }

    private static func fetchCurrentPeriodUsage(accessToken: String) -> PeriodUsage? {
        guard let data = httpPOST(
            url: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
            ],
            body: [:]
        ) else { return nil }

        let planUsage = data["planUsage"] as? [String: Any]
        let total = clampPercent(doubleValue(planUsage?["totalPercentUsed"]))
        let endMs = doubleValue(data["billingCycleEnd"])
        return PeriodUsage(totalPercentUsed: total, billingCycleEndMs: endMs)
    }

    private static func extractUsageTotals(_ usage: [String: Any]) -> (used: Int, limit: Int) {
        if let gpt4 = usage["gpt-4"] as? [String: Any], let t = bucketTotals(gpt4) {
            return t
        }
        var best: (used: Int, limit: Int)?
        for (key, value) in usage {
            if key == "gpt-4" { continue }
            guard let bucket = value as? [String: Any], let t = bucketTotals(bucket) else { continue }
            if best == nil || t.limit > best!.limit || (t.limit == best!.limit && t.used > best!.used) {
                best = t
            }
        }
        return best ?? (0, 0)
    }

    private static func bucketTotals(_ bucket: [String: Any]) -> (used: Int, limit: Int)? {
        let used = intValue(bucket["numRequests"])
            ?? intValue(bucket["usedRequests"])
            ?? intValue(bucket["requestsUsed"])
            ?? intValue(bucket["includedRequestsUsed"])
        let limit = intValue(bucket["maxRequestUsage"])
            ?? intValue(bucket["maxRequests"])
            ?? intValue(bucket["requestLimit"])
            ?? intValue(bucket["includedRequestLimit"])
        if used == nil && limit == nil { return nil }
        return (used ?? 0, limit ?? 0)
    }

    private static func httpGET(url: String, headers: [String: String]) -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: fetchTimeout)
        req.httpMethod = "GET"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return syncJSON(request: req)
    }

    private static func httpPOST(url: String, headers: [String: String], body: [String: Any]) -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: fetchTimeout)
        req.httpMethod = "POST"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return syncJSON(request: req)
    }

    private static func syncJSON(request: URLRequest) -> [String: Any]? {
        let sem = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { sem.signal() }
            guard let data,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            result = json
        }.resume()
        _ = sem.wait(timeout: .now() + fetchTimeout + 1)
        return result
    }

    private static func nextMonth(fromISO iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let date else { return nil }
        return Calendar.current.date(byAdding: .month, value: 1, to: date)
    }

    private static func clampPercent(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(100, max(0, value))
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Double { return Int(n) }
        if let s = value as? String, let n = Int(s) { return n }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let s = value as? String, let n = Double(s) { return n }
        return nil
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
