import Cocoa
import ServiceManagement
import Sparkle

private let aiUsageIntroURL = URL(string: "https://apps.tomippe.jp/ai-usage/")!
private let appDisplayName = "AI Usage"

/// メニューバー本体の骨格（disk-monitor / ip-monitor 型）。使用量取得は docs/handoff-from-cursor-usage.md に従い後続実装。
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var launchAtLoginMenuItem: NSMenuItem?
    private var placeholderMenuItem: NSMenuItem?
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    func applicationWillFinishLaunching(_: Notification) {
        MoveToApplicationsFolder.moveIfNecessary()
    }

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: appDisplayName) {
            img.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
        }
        statusItem.button?.title = " —"

        let menu = NSMenu()
        menu.delegate = self

        let placeholder = NSMenuItem(
            title: NSLocalizedString("menu.placeholder", comment: ""),
            action: nil,
            keyEquivalent: ""
        )
        placeholder.isEnabled = false
        placeholderMenuItem = placeholder
        menu.addItem(placeholder)
        menu.addItem(.separator())
        menu.addItem(menuItem(NSLocalizedString("menu.refresh", comment: ""), #selector(refreshNow), "r"))

        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(
                title: NSLocalizedString("menu.login_item", comment: ""),
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            loginItem.target = self
            menu.addItem(loginItem)
            launchAtLoginMenuItem = loginItem
            syncLaunchAtLoginItem()
            menu.addItem(.separator())
        }

        menu.addItem(aboutMenuItem())
        menu.addItem(feedbackMenuItem())
        menu.addItem(sparkleCheckForUpdatesMenuItem())
        menu.addItem(.separator())
        menu.addItem(TomippeRelaunch.restartMenuItem(
            appDisplayName: appDisplayName,
            target: self,
            action: #selector(restartApp)
        ))
        menu.addItem(TomippeRelaunch.quitMenuItem(
            appDisplayName: appDisplayName,
            target: self,
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    func menuWillOpen(_: NSMenu) {
        syncLaunchAtLoginItem()
    }

    @objc private func refreshNow() {
        placeholderMenuItem?.title = NSLocalizedString("menu.placeholder", comment: "")
        statusItem.button?.title = " —"
    }

    @objc private func restartApp() {
        TomippeRelaunch.relaunchCurrentApp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func aboutMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(format: NSLocalizedString("menu.about_format", comment: ""), appDisplayName),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    @objc private func showAbout() {
        TomippeAppAbout.show(
            appName: appDisplayName,
            introURL: aiUsageIntroURL,
            checkForUpdates: { [weak self] in
                self?.updaterController.checkForUpdates(nil)
            }
        )
    }

    private func feedbackMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("menu.send_feedback", comment: ""),
            action: #selector(sendFeedback),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    @objc private func sendFeedback() {
        TomippeFeedbackForm.open(appName: appDisplayName)
    }

    private func sparkleCheckForUpdatesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: NSLocalizedString("menu.check_for_updates", comment: ""),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func syncLaunchAtLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        guard let item = launchAtLoginMenuItem else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            item.state = .on
        case .requiresApproval:
            item.state = .mixed
        default:
            item.state = .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        Task {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    try await service.unregister()
                } else {
                    try service.register()
                }
                await MainActor.run {
                    self.syncLaunchAtLoginItem()
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("alert.loginitem_failed_title", comment: "")
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}

@main
struct AIUsageApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
