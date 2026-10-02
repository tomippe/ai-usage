import AppKit
import Foundation

enum ProviderAvailability {
    private static let cursorBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92",
        "com.tomippe.CursorWrap",
    ]
    private static let codexBundleID = "com.openai.codex"
    private static let claudeCodeBundleIDs: Set<String> = ["com.anthropic.claudefordesktop"]

    static func isCursorBundle(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return cursorBundleIDs.contains(bundleID)
    }

    static func isCodexBundle(_ bundleID: String?) -> Bool {
        bundleID == codexBundleID
    }

    static func provider(forBundleID bundleID: String?) -> ProviderKind? {
        if isCursorBundle(bundleID) { return .cursor }
        if isCodexBundle(bundleID) { return .codex }
        if let bundleID, claudeCodeBundleIDs.contains(bundleID) { return .claude }
        return nil
    }

    static func isCursorInstalled() -> Bool {
        if FileManager.default.fileExists(atPath: "/Applications/Cursor.app") { return true }
        let db = cursorDatabasePath()
        return FileManager.default.fileExists(atPath: db)
    }

    static func isCodexInstalled() -> Bool {
        if FileManager.default.fileExists(atPath: "/Applications/ChatGPT.app") { return true }
        return FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex/auth.json")
    }

    static func isClaudeCodeInstalled() -> Bool {
        let home = NSHomeDirectory()
        return FileManager.default.fileExists(atPath: home + "/.claude.json")
            || FileManager.default.fileExists(atPath: home + "/.claude/.credentials.json")
            || FileManager.default.fileExists(atPath: home + "/.local/bin/claude")
            || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/claude")
            || FileManager.default.fileExists(atPath: "/usr/local/bin/claude")
    }

    static func installedProviders() -> [ProviderKind] {
        var list: [ProviderKind] = []
        if isCursorInstalled() { list.append(.cursor) }
        if isCodexInstalled() { list.append(.codex) }
        if isClaudeCodeInstalled() { list.append(.claude) }
        return list
    }

    static func cursorDatabasePath() -> String {
        NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    /// `/Applications/Cursor.app` または登録済み Cursor 系 .app
    static func cursorAppPath() -> String? {
        let candidates = [
            "/Applications/Cursor.app",
            NSHomeDirectory() + "/Applications/Cursor.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
            return url.path
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.tomippe.CursorWrap") {
            return url.path
        }
        return nil
    }

    static func codexAppPath() -> String? {
        let candidates = [
            "/Applications/ChatGPT.app",
            NSHomeDirectory() + "/Applications/ChatGPT.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: codexBundleID) {
            return url.path
        }
        return nil
    }

    static func codexBinaryPath() -> String? {
        var candidates: [String] = []
        if let app = codexAppPath() {
            candidates.append(app + "/Contents/Resources/codex-cli/bin/codex")
            candidates.append(app + "/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        }
        candidates.append("/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        candidates.append("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        candidates.append(NSHomeDirectory() + "/.local/bin/codex")
        candidates.append("/opt/homebrew/bin/codex")
        candidates.append("/usr/local/bin/codex")
        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
