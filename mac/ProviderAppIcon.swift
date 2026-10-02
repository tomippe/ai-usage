import AppKit

/// インストール済みアプリのバンドルからメニューバー用アイコンを読む（リポジトリにコピーしない）。
enum ProviderAppIcon {
    private static let menuBarPointSize: CGFloat = 18

    static func menuBarImage(for provider: ProviderKind) -> NSImage? {
        let path: String?
        switch provider {
        case .cursor:
            path = ProviderAvailability.cursorAppPath()
        case .codex:
            path = ProviderAvailability.codexAppPath()
        }
        guard let path else { return nil }
        return scaledAppIcon(at: path)
    }

    private static func scaledAppIcon(at appPath: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        guard let copy = icon.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: menuBarPointSize, height: menuBarPointSize)
        copy.isTemplate = false
        return copy
    }
}
