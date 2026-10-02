import AppKit
import Foundation

enum ProviderAvailability {
    private static let cursorBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92",
        "com.tomippe.CursorWrap",
    ]
    private static let codexBundleID = "com.openai.codex"

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

    static func installedProviders() -> [ProviderKind] {
        var list: [ProviderKind] = []
        if isCursorInstalled() { list.append(.cursor) }
        if isCodexInstalled() { list.append(.codex) }
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
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
