import Cocoa
import ServiceManagement
import Sparkle

private let aiUsageIntroURL = URL(string: "https://apps.tomippe.jp/ai-usage/")!
private let appDisplayName = "AI Usage"
private let pollInterval: TimeInterval = 300
private let lastProviderDefaultsKey = "jp.tomippe.ai-usage.lastProvider"

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var launchAtLoginMenuItem: NSMenuItem?
    private var providerMenuItems: [ProviderKind: NSMenuItem] = [:]
    private var menuContainer: NSMenu!
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    private var cursorSnapshot: CursorUsageSnapshot?
    private var codexSnapshot: CodexUsageSnapshot?
    private var lastFetchTime: Date?
    private var isFetching = false
    private var pollTimer: Timer?
    private var lastActiveProvider: ProviderKind = .cursor
    private var foregroundProvider: ProviderKind?

    func applicationWillFinishLaunching(_: Notification) {
        MoveToApplicationsFolder.moveIfNecessary()
    }

    func applicationDidFinishLaunching(_: Notification) {
        if let saved = UserDefaults.standard.string(forKey: lastProviderDefaultsKey),
           let provider = ProviderKind(rawValue: saved) {
            lastActiveProvider = provider
        } else if ProviderAvailability.isCursorInstalled() {
            lastActiveProvider = .cursor
        } else if ProviderAvailability.isCodexInstalled() {
            lastActiveProvider = .codex
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyMenuBarIcon()
        statusItem.button?.title = " …"

        menuContainer = NSMenu()
        menuContainer.delegate = self
        rebuildProviderMenuItems()
        menuContainer.addItem(.separator())
        menuContainer.addItem(menuItem(NSLocalizedString("menu.refresh", comment: ""), #selector(refreshNow), "r"))

        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(
                title: NSLocalizedString("menu.login_item", comment: ""),
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            loginItem.target = self
            menuContainer.addItem(loginItem)
            launchAtLoginMenuItem = loginItem
            syncLaunchAtLoginItem()
            menuContainer.addItem(.separator())
        }

        menuContainer.addItem(aboutMenuItem())
        menuContainer.addItem(feedbackMenuItem())
        menuContainer.addItem(sparkleCheckForUpdatesMenuItem())
        menuContainer.addItem(.separator())
        menuContainer.addItem(TomippeRelaunch.restartMenuItem(
            appDisplayName: appDisplayName,
            target: self,
            action: #selector(restartApp)
        ))
        menuContainer.addItem(TomippeRelaunch.quitMenuItem(
            appDisplayName: appDisplayName,
            target: self,
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusItem.menu = menuContainer

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        refreshUsage(force: true)
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refreshUsage(force: false)
        }
    }

    func menuWillOpen(_: NSMenu) {
        syncLaunchAtLoginItem()
        for (provider, item) in providerMenuItems {
            item.title = providerMenuLine(provider: provider)
        }
    }

    private func applyMenuBarIcon() {
        if let img = NSImage(named: "MenuBarIcon") {
            img.isTemplate = false
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
            return
        }
        if let img = NSImage(named: "AppIcon") {
            img.isTemplate = false
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
        }
    }

    @objc private func frontAppChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if let provider = ProviderAvailability.provider(forBundleID: app.bundleIdentifier) {
            foregroundProvider = provider
            lastActiveProvider = provider
            UserDefaults.standard.set(provider.rawValue, forKey: lastProviderDefaultsKey)
            updateStatusBarTitle()
        }
    }

    private func displayProvider() -> ProviderKind? {
        if let foregroundProvider { return foregroundProvider }
        let installed = ProviderAvailability.installedProviders()
        if installed.contains(lastActiveProvider) { return lastActiveProvider }
        return installed.first
    }

    private func updateStatusBarTitle() {
        guard let provider = displayProvider() else {
            statusItem.button?.title = " " + NSLocalizedString("status.no_providers", comment: "")
            return
        }

        switch provider {
        case .cursor:
            if let snap = cursorSnapshot {
                if snap.errorMessage == "not_logged_in" {
                    statusItem.button?.title = " Cursor " + NSLocalizedString("status.not_logged_in", comment: "")
                } else if snap.errorMessage != nil, cursorSnapshot?.totalPercentUsed == nil, snap.limitRequests == 0 {
                    statusItem.button?.title = " Cursor " + NSLocalizedString("status.unavailable", comment: "")
                } else {
                    statusItem.button?.title = " \(provider.displayName) \(snap.statusLineSuffix)"
                }
            } else {
                statusItem.button?.title = " \(provider.displayName) …"
            }
        case .codex:
            if let snap = codexSnapshot {
                if snap.errorMessage != nil, snap.weeklyUsedPercent == nil {
                    statusItem.button?.title = " Codex " + NSLocalizedString("status.unavailable", comment: "")
                } else {
                    statusItem.button?.title = " \(provider.displayName) \(snap.menuBarPercentText)"
                }
            } else {
                statusItem.button?.title = " \(provider.displayName) …"
            }
        }
    }

    private func rebuildProviderMenuItems() {
        for item in providerMenuItems.values {
            menuContainer.removeItem(item)
        }
        providerMenuItems.removeAll()

        let installed = ProviderAvailability.installedProviders()
        guard !installed.isEmpty else {
            let item = NSMenuItem(title: NSLocalizedString("status.no_providers", comment: ""), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menuContainer.insertItem(item, at: 0)
            providerMenuItems[.cursor] = item
            return
        }

        var index = 0
        for provider in installed {
            let title = providerMenuLine(provider: provider)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menuContainer.insertItem(item, at: index)
            providerMenuItems[provider] = item
            index += 1
        }
    }

    private func providerMenuLine(provider: ProviderKind) -> String {
        switch provider {
        case .cursor:
            guard let snap = cursorSnapshot else { return "\(provider.displayName) …" }
            if snap.errorMessage == "not_logged_in" {
                return "\(provider.displayName) — " + NSLocalizedString("status.not_logged_in", comment: "")
            }
            var line = "\(provider.displayName) — \(snap.statusLineSuffix)"
            if let reset = snap.resetsAt {
                line += " · " + formatReset(reset)
            }
            if let plan = snap.planName, !plan.isEmpty {
                line += " · \(plan)"
            }
            return line
        case .codex:
            guard let snap = codexSnapshot else { return "\(provider.displayName) …" }
            if snap.errorMessage != nil, snap.weeklyUsedPercent == nil {
                return "\(provider.displayName) — " + NSLocalizedString("status.unavailable", comment: "")
            }
            var line = "\(provider.displayName) — " + NSLocalizedString("menu.codex_weekly", comment: "") + " \(snap.menuBarPercentText)"
            if let primary = snap.primaryUsedPercent {
                line += " · " + NSLocalizedString("menu.codex_primary", comment: "") + " \(formatPercent(primary))"
            }
            if let reset = snap.weeklyResetsAt {
                line += " · " + formatReset(reset)
            }
            if let plan = snap.planType, !plan.isEmpty {
                line += " · \(plan)"
            }
            return line
        }
    }

    private func formatReset(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return String(format: NSLocalizedString("menu.resets_at", comment: ""), f.string(from: date))
    }

    @objc private func refreshNow() {
        refreshUsage(force: true)
    }

    private func refreshUsage(force: Bool) {
        if isFetching { return }
        if !force, let lastFetchTime, Date().timeIntervalSince(lastFetchTime) < pollInterval {
            updateStatusBarTitle()
            return
        }

        isFetching = true
        statusItem.button?.title = " …"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var cursorResult: CursorUsageSnapshot?
            var codexResult: CodexUsageSnapshot?
            if ProviderAvailability.isCursorInstalled() {
                cursorResult = CursorUsageClient.fetchUsage()
            }
            if ProviderAvailability.isCodexInstalled() {
                codexResult = CodexUsageClient.fetchUsage()
            }
            DispatchQueue.main.async {
                self.isFetching = false
                self.lastFetchTime = Date()
                self.cursorSnapshot = cursorResult
                self.codexSnapshot = codexResult
                self.rebuildProviderMenuItems()
                self.updateStatusBarTitle()
            }
        }
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
        TomippeFeedbackForm.open(appName: "AI Usage by tomippe")
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
