import Cocoa
import ServiceManagement
import Sparkle

private let aiUsageIntroURL = URL(string: "https://apps.tomippe.jp/ai-usage/")!
private let appDisplayName = "AI Usage"
private let pollInterval: TimeInterval = 60
private let noProvidersGracePeriod: TimeInterval = 60
private let lastProviderDefaultsKey = "jp.tomippe.ai-usage.lastProvider"
private let voiceAlertsEnabledDefaultsKey = "jp.tomippe.ai-usage.voiceAlerts.enabled"
private let voiceAlertThresholdDefaultsPrefix = "jp.tomippe.ai-usage.voiceAlerts.threshold."
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
    private var voiceAlertsSubmenu: NSMenu?
    private var voiceAlertsEnabledMenuItem: NSMenuItem?
    private var voiceAlertThresholdMenuItems: [Int: NSMenuItem] = [:]
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private let usageAlertAnnouncer = MacUsageSpeechAnnouncer()
    private var usageAlertMonitor = RemainingUsageAlertMonitor()

    private var cursorSnapshot: CursorUsageSnapshot?
    private var cursorDashboardBundle: CursorDashboardBundle?
    private let cursorDashboardView = CursorDashboardMenuView()
    private var codexSnapshot: CodexUsageSnapshot?
    private var claudeSnapshot: ClaudeUsageSnapshot?
    private var lastFetchTime: Date?
    private var isFetching = false
    private var lastMenuBarTitle: String?
    private var hasReceivedUsageData = false
    private var pollTimer: Timer?
    private var claudeSnapshotTimer: Timer?
    private var lastActiveProvider: ProviderKind = .cursor
    private var foregroundProvider: ProviderKind?
    private var currencyMenuRootItem: NSMenuItem?
    private var isStatusMenuOpen = false
    private var pendingProviderMenuRebuild = false
    private var providerMenuShowsPlaceholder = false
    private var launchedAt = Date()

    func applicationWillFinishLaunching(_: Notification) {
        MoveToApplicationsFolder.moveIfNecessary()
    }

    func applicationDidFinishLaunching(_: Notification) {
        launchedAt = Date()
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
        claudeSnapshot = ClaudeUsageClient.mergeSources(
            oauth: nil,
            statusline: ClaudeUsageClient.readSnapshot(),
            retaining: nil
        )
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
        menuContainer.addItem(buildVoiceAlertsMenuItem())

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
            self.applyClaudeSnapshot(oauth: nil)
        }

        DispatchQueue.main.async { [weak self] in
            self?.applyMenuBarIcon()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + noProvidersGracePeriod) { [weak self] in
            guard let self else { return }
            self.updateStatusBarTitle()
            self.scheduleProviderMenuRebuild()
        }
    }

    private func mayShowNoProvidersMessage() -> Bool {
        Date().timeIntervalSince(launchedAt) >= noProvidersGracePeriod
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
        syncVoiceAlertSettings()
        for (provider, item) in providerMenuItems {
            item.title = providerMenuLine(provider: provider)
        }
        if let bundle = cursorDashboardBundle {
            cursorDashboardView.update(bundle: bundle)
            cursorDashboardView.refreshMenuLayoutSize()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu == voiceAlertsSubmenu {
            usageAlertAnnouncer.stopPreview()
            return
        }
        guard menu == menuContainer else { return }
        usageAlertAnnouncer.stopPreview()
        isStatusMenuOpen = false
        if pendingProviderMenuRebuild {
            pendingProviderMenuRebuild = false
            DispatchQueue.main.async { [weak self] in
                self?.rebuildProviderMenuItems()
            }
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu == voiceAlertsSubmenu else { return }
        guard let threshold = item?.representedObject as? Int else {
            usageAlertAnnouncer.stopPreview()
            return
        }
        usageAlertAnnouncer.preview(UsageThresholdAlert(
            provider: displayProvider() ?? .cursor,
            window: .standard,
            thresholdPercent: threshold
        ))
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

    private func installedProviders() -> [ProviderKind] {
        ProviderAvailability.installedProviders()
    }

    /// メニューバー表示の切り替え対象（インストール済み。使用率の有無は問わない）
    private func displayProvider() -> ProviderKind? {
        let installed = installedProviders()
        guard !installed.isEmpty else { return nil }
        if let foregroundProvider, installed.contains(foregroundProvider) { return foregroundProvider }
        if installed.contains(lastActiveProvider) { return lastActiveProvider }
        return installed.first
    }

    private func applyMenuBarTitle(_ title: String) {
        lastMenuBarTitle = title
        statusItem.button?.title = " " + title
    }

    /// 前面／最後に使ったアプリに合わせ、メニューバーは常に1行だけ表示する。
    private func menuBarTitleForDisplayProvider() -> String? {
        guard let provider = displayProvider() else { return nil }
        let rate = effectiveLocalExchangeRate()

        switch provider {
        case .cursor:
            guard let snap = cursorSnapshot else { return nil }
            if snap.errorMessage == "not_logged_in" {
                hasReceivedUsageData = true
                return NSLocalizedString("status.not_logged_in", comment: "")
            }
            if snap.errorMessage != nil, snap.totalPercentUsed == nil, snap.limitRequests == 0 {
                hasReceivedUsageData = true
                return NSLocalizedString("status.unavailable", comment: "")
            }
            hasReceivedUsageData = true
            return snap.menuBarTitleText(localExchangeRate: rate)
        case .codex:
            guard let snap = codexSnapshot else { return nil }
            if snap.errorMessage != nil, snap.weeklyUsedPercent == nil, snap.primaryUsedPercent == nil {
                hasReceivedUsageData = true
                return NSLocalizedString("status.unavailable", comment: "")
            }
            hasReceivedUsageData = true
            return snap.menuBarTitleText()
        case .claude:
            guard let snap = claudeSnapshot else { return nil }
            if snap.needsCredentialAccessPrompt {
                hasReceivedUsageData = true
                return NSLocalizedString("status.claude_credential_access", comment: "")
            }
            if snap.hasMenuUsage {
                hasReceivedUsageData = true
                return snap.menuBarTitleText()
            }
            hasReceivedUsageData = true
            return NSLocalizedString("status.awaiting_claude_code", comment: "")
        }
    }

    private func updateStatusBarTitle() {
        guard installedProviders().isEmpty == false || mayShowNoProvidersMessage() else {
            if !isFetching, !hasReceivedUsageData {
                applyMenuBarTitle("…")
            }
            return
        }

        if installedProviders().isEmpty {
            if mayShowNoProvidersMessage() {
                applyMenuBarTitle(NSLocalizedString("status.no_providers", comment: ""))
            } else if !isFetching, lastMenuBarTitle == nil {
                applyMenuBarTitle("…")
            }
            return
        }

        if let title = menuBarTitleForDisplayProvider() {
            applyMenuBarTitle(title)
            return
        }

        if isFetching, lastMenuBarTitle != nil {
            return
        }

        if !hasReceivedUsageData {
            applyMenuBarTitle("…")
        }
    }

    /// ポーリング完了時は呼ばない（メニュー表示中に項目を外すと落ちる）。タイトルだけ更新する。
    private func syncProviderMenuItemTitles() {
        let visible = menuProviders()
        let needsRebuild = providerMenuShowsPlaceholder
            || Set(visible) != Set(providerMenuItems.keys)
        if needsRebuild {
            if isStatusMenuOpen {
                pendingProviderMenuRebuild = true
            } else {
                scheduleProviderMenuRebuild()
            }
            return
        }
        for (provider, item) in providerMenuItems {
            item.title = providerMenuLine(provider: provider)
        }
    }

    private func scheduleProviderMenuRebuild() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isStatusMenuOpen else {
                self?.pendingProviderMenuRebuild = true
                return
            }
            self.rebuildProviderMenuItems()
        }
    }

    private func rebuildProviderMenuItems() {
        providerMenuShowsPlaceholder = false
        for item in providerMenuItems.values {
            if item.submenu != nil {
                item.submenu?.removeAllItems()
            }
            menuContainer.removeItem(item)
        }
        providerMenuItems.removeAll()

        let visible = menuProviders()
        guard !visible.isEmpty else {
            providerMenuItems.removeAll()
            if installedProviders().isEmpty, mayShowNoProvidersMessage() {
                let item = NSMenuItem(
                    title: NSLocalizedString("status.no_providers", comment: ""),
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                menuContainer.insertItem(item, at: 0)
                providerMenuShowsPlaceholder = true
            } else {
                providerMenuShowsPlaceholder = false
            }
            return
        }

        var index = 0
        for provider in visible {
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

    private func menuProviders() -> [ProviderKind] {
        ProviderAvailability.installedProviders().filter(providerHasMenuUsage)
    }

    private func providerHasMenuUsage(_ provider: ProviderKind) -> Bool {
        switch provider {
        case .cursor:
            return cursorSnapshot?.hasMenuUsage == true
        case .codex:
            return codexSnapshot?.hasMenuUsage == true
        case .claude:
            return claudeSnapshot?.hasMenuUsage == true
        }
    }

    @objc private func activateProviderApp(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let provider = ProviderKind(rawValue: raw) else { return }
        activateApplication(for: provider)
    }

    private func activateApplication(for provider: ProviderKind) {
        if provider == .claude {
            if claudeSnapshot?.needsCredentialAccessPrompt == true {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let snap = ClaudeUsageClient.requestCredentialAccessAndFetchUsage()
                    self.applyClaudeSnapshot(oauth: snap)
                    if snap.needsCredentialAccessPrompt {
                        return
                    }
                    self.foregroundProvider = nil
                    self.lastActiveProvider = .claude
                    UserDefaults.standard.set(ProviderKind.claude.rawValue, forKey: lastProviderDefaultsKey)
                    self.updateStatusBarTitle()
                    self.applyMenuBarIcon()
                    self.scheduleProviderMenuRebuild()
                }
                return
            }
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
            guard let snap = claudeSnapshot, snap.hasMenuUsage else { return "" }
            return snap.claudeMenuItemTitle()
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

    private func buildVoiceAlertsMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: NSLocalizedString("menu.voice_alerts", comment: ""), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        voiceAlertsSubmenu = submenu

        let enabledItem = NSMenuItem(
            title: NSLocalizedString("menu.voice_alerts_enabled", comment: ""),
            action: #selector(toggleVoiceAlerts),
            keyEquivalent: ""
        )
        enabledItem.target = self
        submenu.addItem(enabledItem)
        voiceAlertsEnabledMenuItem = enabledItem
        submenu.addItem(.separator())

        for threshold in RemainingUsageAlertMonitor.supportedThresholds {
            let title = String(
                format: NSLocalizedString("menu.voice_alert_threshold", comment: ""),
                threshold
            )
            let item = NSMenuItem(title: title, action: #selector(toggleVoiceAlertThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = threshold
            submenu.addItem(item)
            voiceAlertThresholdMenuItems[threshold] = item
        }

        root.submenu = submenu
        syncVoiceAlertSettings()
        return root
    }

    private var voiceAlertsEnabled: Bool {
        UserDefaults.standard.bool(forKey: voiceAlertsEnabledDefaultsKey)
    }

    private func isVoiceAlertThresholdEnabled(_ threshold: Int) -> Bool {
        let key = voiceAlertThresholdDefaultsPrefix + String(threshold)
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func selectedVoiceAlertThresholds() -> Set<Int> {
        Set(RemainingUsageAlertMonitor.supportedThresholds.filter { isVoiceAlertThresholdEnabled($0) })
    }

    private func syncVoiceAlertSettings() {
        let enabled = voiceAlertsEnabled
        voiceAlertsEnabledMenuItem?.state = enabled ? .on : .off
        for (threshold, item) in voiceAlertThresholdMenuItems {
            item.state = isVoiceAlertThresholdEnabled(threshold) ? .on : .off
        }
    }

    @objc private func toggleVoiceAlerts() {
        UserDefaults.standard.set(!voiceAlertsEnabled, forKey: voiceAlertsEnabledDefaultsKey)
        syncVoiceAlertSettings()
    }

    @objc private func toggleVoiceAlertThreshold(_ sender: NSMenuItem) {
        guard let threshold = sender.representedObject as? Int else { return }
        let key = voiceAlertThresholdDefaultsPrefix + String(threshold)
        UserDefaults.standard.set(!isVoiceAlertThresholdEnabled(threshold), forKey: key)
        syncVoiceAlertSettings()
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

    private func applyClaudeSnapshot(oauth: ClaudeUsageSnapshot?) {
        let merged = ClaudeUsageClient.mergeSources(
            oauth: oauth,
            statusline: ClaudeUsageClient.readSnapshot(),
            retaining: claudeSnapshot
        )
        let changed = merged?.fetchedAt != claudeSnapshot?.fetchedAt
            || merged?.fiveHourUsedPercent != claudeSnapshot?.fiveHourUsedPercent
            || merged?.sevenDayUsedPercent != claudeSnapshot?.sevenDayUsedPercent
            || merged?.errorMessage != claudeSnapshot?.errorMessage
        guard changed else { return }
        claudeSnapshot = merged
        evaluateUsageAlert(provider: .claude, window: .fiveHour, remainingPercent: merged?.fiveHourUsedPercent.map { remainingPercent(fromUsed: $0) })
        evaluateUsageAlert(provider: .claude, window: .weekly, remainingPercent: merged?.sevenDayUsedPercent.map { remainingPercent(fromUsed: $0) })
        updateStatusBarTitle()
        syncProviderMenuItemTitles()
        if oauth != nil, !isStatusMenuOpen {
            scheduleProviderMenuRebuild()
        }
    }

    private func refreshUsage(force: Bool) {
        if isFetching { return }
        if !force, let lastFetchTime, Date().timeIntervalSince(lastFetchTime) < pollInterval {
            updateStatusBarTitle()
            return
        }

        isFetching = true

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
            var claudeOAuth: ClaudeUsageSnapshot?
            if ProviderAvailability.isClaudeCodeInstalled() {
                claudeOAuth = ClaudeUsageClient.fetchOAuthUsage()
            }
            DispatchQueue.main.async {
                self.isFetching = false
                self.lastFetchTime = Date()
                self.cursorSnapshot = cursorResult
                self.cursorDashboardBundle = cursorDash
                if let cursorDash, !self.isStatusMenuOpen {
                    self.cursorDashboardView.update(bundle: cursorDash)
                }
                self.codexSnapshot = codexResult
                self.evaluateCursorUsageAlerts(cursorResult)
                self.evaluateUsageAlert(provider: .codex, window: .fiveHour, remainingPercent: codexResult?.primaryUsedPercent.map { remainingPercent(fromUsed: $0) })
                self.evaluateUsageAlert(provider: .codex, window: .weekly, remainingPercent: codexResult?.weeklyUsedPercent.map { remainingPercent(fromUsed: $0) })
                self.applyClaudeSnapshot(oauth: claudeOAuth)
                self.syncProviderMenuItemTitles()
                self.updateStatusBarTitle()
                self.applyMenuBarIcon()
                self.refreshExchangeRateIfNeeded(for: cursorResult)
            }
        }
    }

    private func cursorRemainingPercent(_ snapshot: CursorUsageSnapshot?) -> Double? {
        guard let snapshot, snapshot.errorMessage != "not_logged_in" else { return nil }
        if let usedPercent = snapshot.totalPercentUsed {
            return remainingPercent(fromUsed: usedPercent)
        }
        guard snapshot.limitRequests > 0 else { return nil }
        let remainingRequests = max(0, snapshot.limitRequests - snapshot.usedRequests)
        return Double(remainingRequests) / Double(snapshot.limitRequests) * 100
    }

    private func evaluateCursorUsageAlerts(_ snapshot: CursorUsageSnapshot?) {
        guard let snapshot, snapshot.errorMessage != "not_logged_in" else {
            evaluateUsageAlert(provider: .cursor, window: .cursorNative, remainingPercent: nil)
            evaluateUsageAlert(provider: .cursor, window: .cursorAPI, remainingPercent: nil)
            evaluateUsageAlert(provider: .cursor, remainingPercent: nil)
            return
        }
        if snapshot.autoPercentUsed != nil || snapshot.apiPercentUsed != nil {
            evaluateUsageAlert(provider: .cursor, window: .cursorNative, remainingPercent: snapshot.autoPercentUsed.map { remainingPercent(fromUsed: $0) })
            evaluateUsageAlert(provider: .cursor, window: .cursorAPI, remainingPercent: snapshot.apiPercentUsed.map { remainingPercent(fromUsed: $0) })
            evaluateUsageAlert(provider: .cursor, remainingPercent: nil)
        } else {
            evaluateUsageAlert(provider: .cursor, window: .cursorNative, remainingPercent: nil)
            evaluateUsageAlert(provider: .cursor, window: .cursorAPI, remainingPercent: nil)
            evaluateUsageAlert(provider: .cursor, remainingPercent: cursorRemainingPercent(snapshot))
        }
    }

    private func codexRemainingPercent(_ snapshot: CodexUsageSnapshot?) -> Double? {
        guard let snapshot else { return nil }
        return [snapshot.primaryUsedPercent, snapshot.weeklyUsedPercent]
            .compactMap { $0 }
            .map { remainingPercent(fromUsed: $0) }
            .min()
    }

    private func claudeRemainingPercent(_ snapshot: ClaudeUsageSnapshot?) -> Double? {
        guard let snapshot, !snapshot.needsCredentialAccessPrompt else { return nil }
        return [snapshot.fiveHourUsedPercent, snapshot.sevenDayUsedPercent]
            .compactMap { $0 }
            .map { remainingPercent(fromUsed: $0) }
            .min()
    }

    private func evaluateUsageAlert(provider: ProviderKind, window: UsageAlertWindow = .standard, remainingPercent: Double?) {
        let enabledThresholds = voiceAlertsEnabled ? selectedVoiceAlertThresholds() : []
        guard let alert = usageAlertMonitor.observe(
            provider: provider,
            window: window,
            remainingPercent: remainingPercent,
            enabledThresholds: enabledThresholds
        ) else { return }
        usageAlertAnnouncer.announce(alert)
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
        TomippeFeedbackForm.open(appName: "AI Usage")
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
