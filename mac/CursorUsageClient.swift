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

    static func fetchDashboardBundle() -> CursorDashboardBundle {
        let snapshot = fetchUsage()
        guard snapshot.errorMessage != "not_installed", snapshot.errorMessage != "not_logged_in" else {
            return CursorDashboardBundle(snapshot: snapshot, events: [], dailySpend: [])
        }
        let events = fetchUsageEvents()
        let daily = fetchDailySpendRows()
        return CursorDashboardBundle(snapshot: snapshot, events: events, dailySpend: daily)
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
            planName: nil, totalPercentUsed: nil, autoPercentUsed: nil, apiPercentUsed: nil,
            onDemand: .disabled, onDemandSpendDollars: 0, onDemandLimitDollars: nil,
            usedRequests: 0, limitRequests: 0,
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
            autoPercentUsed: nil,
            apiPercentUsed: nil,
            onDemand: setup.onDemandEnabled ? .limited : .disabled,
            onDemandSpendDollars: 0,
            onDemandLimitDollars: setup.onDemandEnabled ? 0 : nil,
            usedRequests: totals.used,
            limitRequests: totals.limit,
            resetsAt: resetsAt,
            fetchedAt: now,
            errorMessage: nil
        )
        if let period = fetchCurrentPeriodUsage(accessToken: auth.accessToken) {
            applyPeriod(&snapshot, period: period, onDemandEnabled: setup.onDemandEnabled)
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
            autoPercentUsed: nil,
            apiPercentUsed: nil,
            onDemand: setup.onDemandEnabled ? .limited : .disabled,
            onDemandSpendDollars: 0,
            onDemandLimitDollars: nil,
            usedRequests: used,
            limitRequests: limit,
            resetsAt: resetsAt,
            fetchedAt: now,
            errorMessage: nil
        )
        if let period = fetchCurrentPeriodUsage(accessToken: auth.accessToken) {
            applyPeriod(&snapshot, period: period, onDemandEnabled: setup.onDemandEnabled)
        }
        return snapshot
    }

    private struct PeriodUsage {
        var totalPercentUsed: Double?
        var autoPercentUsed: Double?
        var apiPercentUsed: Double?
        var billingCycleEndMs: Double?
        var onDemandSpendDollars: Double?
        var onDemandLimitDollars: Double?
    }

    private static func applyPeriod(_ snapshot: inout CursorUsageSnapshot, period: PeriodUsage, onDemandEnabled: Bool) {
        if let pct = period.totalPercentUsed { snapshot.totalPercentUsed = pct }
        snapshot.autoPercentUsed = period.autoPercentUsed
        snapshot.apiPercentUsed = period.apiPercentUsed
        if let end = period.billingCycleEndMs {
            snapshot.resetsAt = Date(timeIntervalSince1970: end / 1000)
        }
        if onDemandEnabled, let limit = period.onDemandLimitDollars, limit > 0 {
            snapshot.onDemand = .limited
            snapshot.onDemandLimitDollars = limit
            snapshot.onDemandSpendDollars = period.onDemandSpendDollars ?? snapshot.onDemandSpendDollars
        }
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
        let spendLimit = data["spendLimitUsage"] as? [String: Any]
        var limitDollars: Double?
        var spendDollars: Double?
        if let spendLimit {
            let limitCents = doubleValue(spendLimit["individualLimit"]) ?? doubleValue(spendLimit["pooledLimit"])
            let usedCents = doubleValue(spendLimit["individualUsed"]) ?? doubleValue(spendLimit["pooledUsed"])
            if let limitCents, limitCents > 0 { limitDollars = limitCents / 100 }
            if let usedCents { spendDollars = usedCents / 100 }
        }
        return PeriodUsage(
            totalPercentUsed: clampPercent(doubleValue(planUsage?["totalPercentUsed"])),
            autoPercentUsed: clampPercent(doubleValue(planUsage?["autoPercentUsed"])),
            apiPercentUsed: clampPercent(doubleValue(planUsage?["apiPercentUsed"])),
            billingCycleEndMs: doubleValue(data["billingCycleEnd"]),
            onDemandSpendDollars: spendDollars,
            onDemandLimitDollars: limitDollars
        )
    }

    static func fetchUsageEvents() -> [CursorUsageEvent] {
        guard let auth = loadAuth(), let setup = ensureSetup(auth: auth) else { return [] }
        let headers = cursorHeaders(sessionToken: auth.sessionToken)
        let teamId = setup.teamId ?? 0
        let endDate = Date().timeIntervalSince1970 * 1000
        let startDate = endDate - 31 * 86_400_000
        var page = 1
        var all: [CursorUsageEvent] = []
        while page <= 10 {
            guard let data = httpPOST(
                url: "https://cursor.com/api/dashboard/get-filtered-usage-events",
                headers: headers,
                body: [
                    "teamId": teamId,
                    "startDate": String(format: "%.0f", startDate),
                    "endDate": String(format: "%.0f", endDate),
                    "page": page,
                    "pageSize": 500,
                ]
            ) else { break }
            let events = data["usageEventsDisplay"] as? [[String: Any]] ?? []
            for e in events {
                let tok = e["tokenUsage"] as? [String: Any] ?? [:]
                let tokens = (intValue(tok["inputTokens"]) ?? 0)
                    + (intValue(tok["outputTokens"]) ?? 0)
                    + (intValue(tok["cacheWriteTokens"]) ?? 0)
                    + (intValue(tok["cacheReadTokens"]) ?? 0)
                let kindRaw = e["kind"] as? String ?? ""
                let kind: String
                if kindRaw == "USAGE_EVENT_KIND_USAGE_BASED" { kind = "On-Demand" }
                else if kindRaw.contains("ERRORED") { kind = "Errored" }
                else if kindRaw.contains("ABORTED") { kind = "Aborted" }
                else { kind = "Included" }
                all.append(CursorUsageEvent(
                    timestamp: doubleValue(e["timestamp"]) ?? 0,
                    model: e["model"] as? String ?? "unknown",
                    kind: kind,
                    totalTokens: tokens,
                    requests: doubleValue(e["requestsCosts"]) ?? doubleValue(e["numRequests"]) ?? 1,
                    spendCents: intValue(e["chargedCents"]) ?? 0
                ))
            }
            if events.count < 500 { break }
            page += 1
        }
        return all
    }

    static func fetchDailySpendRows() -> [CursorDailySpendRow] {
        guard let auth = loadAuth(), let setup = ensureSetup(auth: auth),
              setup.isTeamMember, let teamId = setup.teamId else { return [] }
        let headers = cursorHeaders(sessionToken: auth.sessionToken)
        let endMs = Date().timeIntervalSince1970 * 1000
        let startMs = endMs - 31 * 86_400_000
        guard let dashboardUserId = resolveDashboardUserId(auth: auth, headers: headers, setup: setup),
              let data = httpPOST(
                url: "https://cursor.com/api/dashboard/get-daily-spend-by-category",
                headers: headers,
                body: [
                    "teamId": teamId,
                    "userId": dashboardUserId,
                    "periodStartMs": Int(startMs),
                    "periodEndMs": Int(endMs),
                    "groupBy": 1,
                    "spendType": 1,
                ]
              )
        else { return [] }
        let rows = data["dailySpend"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let day = doubleValue(row["day"]),
                  let category = row["category"] as? String,
                  let spend = intValue(row["spendCents"]),
                  let tokens = intValue(row["totalTokens"]) else { return nil }
            return CursorDailySpendRow(day: day, category: category, spendCents: spend, totalTokens: tokens)
        }
    }

    private static func resolveDashboardUserId(auth: AuthInfo, headers: [String: String], setup: SetupCache) -> Int? {
        if let n = Int(auth.userId) { return n }
        guard setup.isTeamMember, let teamId = setup.teamId,
              let data = httpPOST(
                url: "https://cursor.com/api/dashboard/get-team-spend",
                headers: headers,
                body: ["teamId": teamId]
              )
        else { return nil }
        let members = data["teamMemberSpend"] as? [[String: Any]] ?? []
        for member in members {
            if (member["email"] as? String) == auth.email,
               let uid = intValue(member["userId"]) { return uid }
        }
        return nil
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
