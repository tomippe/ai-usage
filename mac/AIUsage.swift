import Cocoa
import ServiceManagement
import Sparkle

private let aiUsageIntroURL = URL(string: "https://apps.tomippe.jp/ai-usage/")!
private let appDisplayName = "AI Usage"
private let pollInterval: TimeInterval = 300
private let lastProviderDefaultsKey = "jp.tomippe.ai-usage.lastProvider"
private extension Notification.Name {
    static let applicationDidChangeEffectiveAppearance = Notification.Name(
        "NSApplicationDidChangeEffectiveAppearanceNotification"
    )
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var launchAtLoginMenuItem: NSMenuItem?
    private var providerMenuItems: [ProviderKind: NSMenuItem] = [:]
    private var menuContainer: NSMenu!
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    private var cursorSnapshot: CursorUsageSnapshot?
    private var cursorDashboardBundle: CursorDashboardBundle?
    private let cursorDashboardView = CursorDashboardMenuView()
    private var codexSnapshot: CodexUsageSnapshot?
    private var claudeSnapshot: ClaudeUsageSnapshot?
    private var lastFetchTime: Date?
    private var isFetching = false
    private var pollTimer: Timer?
    private var claudeSnapshotTimer: Timer?
    private var lastActiveProvider: ProviderKind = .cursor
    private var foregroundProvider: ProviderKind?
    private var currencyMenuRootItem: NSMenuItem?
    private var isStatusMenuOpen = false
    private var pendingProviderMenuRebuild = false

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
        if let executablePath = Bundle.main.executablePath {
            ClaudeUsageClient.installStatusLineIfAvailable(executablePath: executablePath)
        }
        claudeSnapshot = ClaudeUsageClient.readSnapshot()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEffectiveAppearanceChanged),
            name: .applicationDidChangeEffectiveAppearance,
            object: nil
        )
        applyMenuBarIcon()
        statusItem.button?.title = " …"

        menuContainer = NSMenu()
        menuContainer.delegate = self
        rebuildProviderMenuItems()
        menuContainer.addItem(.separator())
        menuContainer.addItem(menuItem(NSLocalizedString("menu.refresh", comment: ""), #selector(refreshNow), "r"))
        menuContainer.addItem(buildCurrencyMenuItem())

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
        claudeSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snapshot = ClaudeUsageClient.readSnapshot()
            if snapshot?.fetchedAt != self.claudeSnapshot?.fetchedAt {
                self.claudeSnapshot = snapshot
                self.updateStatusBarTitle()
                self.syncProviderMenuItemTitles()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.applyMenuBarIcon()
        }
    }

    @objc private func handleEffectiveAppearanceChanged() {
        applyMenuBarIcon()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu != menuContainer {
            if menu.items.first?.view === cursorDashboardView, let bundle = cursorDashboardBundle {
                cursorDashboardView.update(bundle: bundle)
                cursorDashboardView.refreshMenuLayoutSize()
            }
            return
        }
        isStatusMenuOpen = true
        syncLaunchAtLoginItem()
        syncCurrencyMenuSelection()
        for (provider, item) in providerMenuItems {
            item.title = providerMenuLine(provider: provider)
        }
        if let bundle = cursorDashboardBundle {
            cursorDashboardView.update(bundle: bundle)
            cursorDashboardView.refreshMenuLayoutSize()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu == menuContainer else { return }
        isStatusMenuOpen = false
        if pendingProviderMenuRebuild {
            pendingProviderMenuRebuild = false
            rebuildProviderMenuItems()
        }
    }

    /// メニューバー色はシステム Dark Mode ではなく status item の effectiveAppearance に従う。描画はテンプレートに任せる。
    private func applyMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        if let provider = displayProvider(), let appIcon = ProviderAppIcon.menuBarImage(for: provider) {
            button.image = appIcon
            button.image?.isTemplate = false
        } else {
            button.image = MenuBarIconRenderer.makeTemplateImage()
            button.image?.isTemplate = true
        }
        button.imagePosition = .imageLeading
        button.contentTintColor = nil
        logMenuBarAppearance(context: "applyMenuBarIcon")
    }

    private func logMenuBarAppearance(context: String) {
        let button = statusItem?.button
        let statusAppearance = button?.effectiveAppearance.name.rawValue ?? "nil"
        let appAppearance = NSApp.effectiveAppearance.name.rawValue
        let best = button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "nil"
        let template = button?.image?.isTemplate == true ? "yes" : "no"
        NSLog(
            "AI Usage menubar icon [%@]: statusButton.effectiveAppearance=%@ bestMatch=%@ NSApp.effectiveAppearance=%@ image.isTemplate=%@",
            context,
            statusAppearance,
            best,
            appAppearance,
            template
        )
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
            applyMenuBarIcon()
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
                    statusItem.button?.title = " " + NSLocalizedString("status.not_logged_in", comment: "")
                } else if snap.errorMessage != nil, cursorSnapshot?.totalPercentUsed == nil, snap.limitRequests == 0 {
                    statusItem.button?.title = " " + NSLocalizedString("status.unavailable", comment: "")
                } else {
                    statusItem.button?.title = " " + snap.menuBarTitleText(localExchangeRate: effectiveLocalExchangeRate())
                }
            } else {
                statusItem.button?.title = " …"
            }
        case .codex:
            if let snap = codexSnapshot {
                if snap.errorMessage != nil, snap.weeklyUsedPercent == nil, snap.primaryUsedPercent == nil {
                    statusItem.button?.title = " " + NSLocalizedString("status.unavailable", comment: "")
                } else {
                    statusItem.button?.title = " " + snap.menuBarTitleText()
                }
            } else {
                statusItem.button?.title = " …"
            }
        case .claude:
            if let snap = claudeSnapshot, snap.fiveHourUsedPercent != nil || snap.sevenDayUsedPercent != nil {
                statusItem.button?.title = " " + snap.menuBarTitleText()
            } else {
                statusItem.button?.title = " " + NSLocalizedString("status.awaiting_claude_code", comment: "")
            }
        }
    }

    /// ポーリング完了時は呼ばない（メニュー表示中に項目を外すと落ちる）。タイトルだけ更新する。
    private func syncProviderMenuItemTitles() {
        let installed = ProviderAvailability.installedProviders()
        if Set(installed) != Set(providerMenuItems.keys) {
            if isStatusMenuOpen {
                pendingProviderMenuRebuild = true
            } else {
                rebuildProviderMenuItems()
            }
            return
        }
        for (provider, item) in providerMenuItems {
            item.title = providerMenuLine(provider: provider)
        }
    }

    private func rebuildProviderMenuItems() {
        for item in providerMenuItems.values {
            if item.submenu != nil {
                item.submenu?.removeAllItems()
            }
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
            let item = NSMenuItem(title: title, action: #selector(activateProviderApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            if provider == .cursor {
                let sub = NSMenu()
                sub.delegate = self
                let dashItem = NSMenuItem()
                dashItem.view = cursorDashboardView
                sub.addItem(dashItem)
                item.submenu = sub
            }
            menuContainer.insertItem(item, at: index)
            providerMenuItems[provider] = item
            index += 1
        }
    }

    @objc private func activateProviderApp(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let provider = ProviderKind(rawValue: raw) else { return }
        activateApplication(for: provider)
    }

    private func activateApplication(for provider: ProviderKind) {
        if provider == .claude {
            foregroundProvider = nil
            lastActiveProvider = provider
            UserDefaults.standard.set(provider.rawValue, forKey: lastProviderDefaultsKey)
            updateStatusBarTitle()
            applyMenuBarIcon()
            return
        }
        let appURL: URL? = {
            switch provider {
            case .cursor:
                guard let path = ProviderAvailability.cursorAppPath() else { return nil }
                return URL(fileURLWithPath: path)
            case .codex:
                guard let path = ProviderAvailability.codexAppPath() else { return nil }
                return URL(fileURLWithPath: path)
            case .claude:
                return nil
            }
        }()
        guard let appURL else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if error == nil {
                    self.foregroundProvider = provider
                    self.lastActiveProvider = provider
                    UserDefaults.standard.set(provider.rawValue, forKey: lastProviderDefaultsKey)
                    self.updateStatusBarTitle()
                    self.applyMenuBarIcon()
                }
            }
        }
    }

    private func providerMenuLine(provider: ProviderKind) -> String {
        switch provider {
        case .cursor:
            guard let snap = cursorSnapshot else { return "\(provider.displayName) …" }
            if snap.errorMessage == "not_logged_in" {
                return "\(provider.displayName) — " + NSLocalizedString("status.not_logged_in", comment: "")
            }
            return snap.cursorMenuItemTitle(localExchangeRate: effectiveLocalExchangeRate())
        case .codex:
            let name = provider.menuDisplayName
            guard let snap = codexSnapshot else { return "\(name) …" }
            if snap.errorMessage != nil, snap.weeklyUsedPercent == nil, snap.primaryUsedPercent == nil {
                return "\(name) — " + NSLocalizedString("status.unavailable", comment: "")
            }
            return snap.codexMenuItemTitle()
        case .claude:
            guard let snap = claudeSnapshot else { return "Claude — " + NSLocalizedString("status.awaiting_claude_code", comment: "") }
            return snap.menuItemTitle()
        }
    }

    private func effectiveLocalExchangeRate() -> Double? {
        ExchangeRateService.effectiveRate(for: DisplayCurrency.current)
    }

    private func buildCurrencyMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: NSLocalizedString("menu.currency", comment: ""), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for currency in DisplayCurrency.allCases {
            let item = NSMenuItem(
                title: NSLocalizedString(currency.menuTitleKey, comment: ""),
                action: #selector(selectDisplayCurrency(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = currency.rawValue
            item.state = DisplayCurrency.current == currency ? .on : .off
            submenu.addItem(item)
        }
        root.submenu = submenu
        currencyMenuRootItem = root
        return root
    }

    private func syncCurrencyMenuSelection() {
        guard let submenu = currencyMenuRootItem?.submenu else { return }
        for item in submenu.items {
            guard let raw = item.representedObject as? String,
                  let currency = DisplayCurrency(rawValue: raw) else { continue }
            item.state = DisplayCurrency.current == currency ? .on : .off
        }
    }

    @objc private func selectDisplayCurrency(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let currency = DisplayCurrency(rawValue: raw) else { return }
        DisplayCurrency.setCurrent(currency)
        syncCurrencyMenuSelection()
        refreshExchangeRateIfNeeded(for: cursorSnapshot)
        updateStatusBarTitle()
        for (provider, item) in providerMenuItems {
            item.title = providerMenuLine(provider: provider)
        }
        if let bundle = cursorDashboardBundle {
            cursorDashboardView.update(bundle: bundle)
            cursorDashboardView.refreshMenuLayoutSize()
        }
    }

    private func refreshExchangeRateIfNeeded(for snapshot: CursorUsageSnapshot?) {
        _ = snapshot
        let currency = DisplayCurrency.current
        guard currency != .usd else { return }
        ExchangeRateService.fetchUSD(to: currency) { [weak self] rate in
            guard let self else { return }
            if let rate {
                ExchangeRateService.setLiveRate(rate, for: currency)
            }
            self.updateStatusBarTitle()
            for (provider, item) in self.providerMenuItems {
                item.title = self.providerMenuLine(provider: provider)
            }
            if let bundle = self.cursorDashboardBundle {
                self.cursorDashboardView.update(bundle: bundle)
                self.cursorDashboardView.refreshMenuLayoutSize()
            }
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
            var cursorDash: CursorDashboardBundle?
            var codexResult: CodexUsageSnapshot?
            if ProviderAvailability.isCursorInstalled() {
                cursorDash = CursorUsageClient.fetchDashboardBundle()
                cursorResult = cursorDash?.snapshot
            }
            if ProviderAvailability.isCodexInstalled() {
                codexResult = CodexUsageClient.fetchUsage()
            }
            DispatchQueue.main.async {
                self.isFetching = false
                self.lastFetchTime = Date()
                self.cursorSnapshot = cursorResult
                self.cursorDashboardBundle = cursorDash
                if let cursorDash {
                    self.cursorDashboardView.update(bundle: cursorDash)
                }
                self.codexSnapshot = codexResult
                self.syncProviderMenuItemTitles()
                self.updateStatusBarTitle()
                self.applyMenuBarIcon()
                self.refreshExchangeRateIfNeeded(for: cursorResult)
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
        if CommandLine.arguments.contains("--claude-statusline") {
            ClaudeUsageClient.consumeStatusLineInput()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
