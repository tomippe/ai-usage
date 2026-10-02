import Cocoa

// 見た目の正本: cursor-usage/media/dashboard/dashboard.css + dashboard.js (PALETTE)
private enum CursorDashboardTheme {
    static let cardFill = NSColor.windowBackgroundColor
    static let cardBorder = NSColor.separatorColor.withAlphaComponent(0.35)
    static let barTrack = NSColor.labelColor.withAlphaComponent(0.08)
    static let barFill = NSColor.labelColor.withAlphaComponent(0.85)
    static let muted = NSColor.secondaryLabelColor
    static let gridGap: CGFloat = 12
    static let cardCorner: CGFloat = 8

    // dashboard.js PALETTE
    static let chartColors: [NSColor] = [
        NSColor(srgbRed: 0.62, green: 0.77, blue: 0.996, alpha: 1),
        NSColor(srgbRed: 0.714, green: 0.89, blue: 0.757, alpha: 1),
        NSColor(srgbRed: 0.969, green: 0.773, blue: 0.627, alpha: 1),
        NSColor(srgbRed: 0.827, green: 0.725, blue: 0.949, alpha: 1),
        NSColor(srgbRed: 0.961, green: 0.722, blue: 0.773, alpha: 1),
        NSColor(srgbRed: 0.655, green: 0.878, blue: 0.878, alpha: 1),
        NSColor(srgbRed: 0.941, green: 0.851, blue: 0.608, alpha: 1),
        NSColor(srgbRed: 0.788, green: 0.831, blue: 0.941, alpha: 1),
    ]
}

final class CursorDashboardMenuView: NSView {
    private let panelWidth: CGFloat = 380
    private let stack = NSStackView()
    private let cardsGrid = NSGridView()
    private let durationRow = NSStackView()
    private var durationButtons: [NSButton] = []
    private let chartView = DailyUsageChartView()
    private let tableScroll = NSScrollView()
    private let tableView = NSTableView()
    private var bundle: CursorDashboardBundle?
    private var duration: UsageDuration = .billingCycle

    override var intrinsicContentSize: NSSize {
        NSSize(width: panelWidth, height: 430)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 430))
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let title = NSTextField(labelWithString: NSLocalizedString("dash.title", comment: ""))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(title)

        cardsGrid.rowSpacing = CursorDashboardTheme.gridGap
        cardsGrid.columnSpacing = CursorDashboardTheme.gridGap
        cardsGrid.xPlacement = .fill
        cardsGrid.yPlacement = .fill
        stack.addArrangedSubview(cardsGrid)

        durationRow.orientation = .horizontal
        durationRow.spacing = 4
        durationRow.distribution = .fillEqually
        for (idx, dur) in UsageDuration.allCases.enumerated() {
            let btn = NSButton(title: NSLocalizedString(dur.menuLabelKey, comment: ""), target: self, action: #selector(durationTapped(_:)))
            btn.tag = idx
            btn.setButtonType(.pushOnPushOff)
            btn.bezelStyle = .recessed
            btn.font = .systemFont(ofSize: 11, weight: .medium)
            btn.controlSize = .small
            durationButtons.append(btn)
            durationRow.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(durationRow)
        updateDurationSelection()

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 128).isActive = true
        stack.addArrangedSubview(chartView)

        let modelTitle = NSTextField(labelWithString: NSLocalizedString("dash.models", comment: ""))
        modelTitle.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(modelTitle)

        tableView.headerView = NSTableHeaderView()
        tableView.addTableColumn(makeColumn("dash.col.model", 148))
        tableView.addTableColumn(makeColumn("dash.col.requests", 72))
        tableView.addTableColumn(makeColumn("dash.col.tokens", 72))
        tableView.addTableColumn(makeColumn("dash.col.spend", 56))
        tableView.rowHeight = 18
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.drawsBackground = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        stack.addArrangedSubview(tableScroll)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    private func makeColumn(_ key: String, _ w: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
        col.title = NSLocalizedString(key, comment: "")
        col.width = w
        return col
    }

    func update(bundle: CursorDashboardBundle) {
        self.bundle = bundle
        rebuildCards(snapshot: bundle.snapshot)
        reloadDurationViews()
    }

    private func clearCardsGrid() {
        while cardsGrid.numberOfRows > 0 {
            cardsGrid.removeRow(at: 0)
        }
    }

    private func rebuildCards(snapshot: CursorUsageSnapshot) {
        clearCardsGrid()
        if let err = snapshot.errorMessage {
            cardsGrid.addRow(with: [
                card(titleKey: "status.unavailable", value: NSLocalizedString(err == "not_logged_in" ? "status.not_logged_in" : "status.unavailable", comment: ""), ratio: nil, footer: nil),
            ])
            return
        }

        let resetFooter = resetFooterText(resetAt: snapshot.resetsAt)
        cardsGrid.addRow(with: [
            card(titleKey: "dash.card.total", value: formatPercent(snapshot.totalPercentUsed ?? 0), ratio: snapshot.totalPercentUsed, footer: resetFooter),
            card(titleKey: "dash.card.auto", value: formatPercent(snapshot.autoPercentUsed ?? 0), ratio: snapshot.autoPercentUsed, footer: nil),
        ])
        cardsGrid.addRow(with: [
            card(titleKey: "dash.card.api", value: formatPercent(snapshot.apiPercentUsed ?? 0), ratio: snapshot.apiPercentUsed, footer: nil),
            card(titleKey: "dash.card.ondemand", value: onDemandText(snapshot), ratio: onDemandRatio(snapshot), footer: onDemandFooter(snapshot)),
        ])
    }

    private func resetFooterText(resetAt: Date?) -> String? {
        guard let resetAt else { return nil }
        let days = max(0, Int(ceil(resetAt.timeIntervalSinceNow / 86_400)))
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .long
        df.timeStyle = .none
        let dateStr = df.string(from: resetAt)
        if days == 1 {
            return String(format: NSLocalizedString("dash.reset.singular", comment: ""), days, dateStr)
        }
        return String(format: NSLocalizedString("dash.reset", comment: ""), days, dateStr)
    }

    private func onDemandFooter(_ s: CursorUsageSnapshot) -> String? {
        switch s.onDemand {
        case .disabled: return nil
        case .unlimited: return NSLocalizedString("dash.ondemand.unlimited", comment: "")
        case .limited: return NSLocalizedString("dash.ondemand.pay_extra", comment: "")
        }
    }

    private func onDemandText(_ s: CursorUsageSnapshot) -> String {
        switch s.onDemand {
        case .disabled:
            return "—"
        case .unlimited:
            return String(format: "$%.2f", s.onDemandSpendDollars)
        case .limited:
            let limit = s.onDemandLimitDollars ?? 0
            return String(format: "$%.2f / $%.2f", s.onDemandSpendDollars, limit)
        }
    }

    private func onDemandRatio(_ s: CursorUsageSnapshot) -> Double? {
        guard s.onDemand == .limited, let limit = s.onDemandLimitDollars, limit > 0 else { return nil }
        return min(100, s.onDemandSpendDollars / limit * 100)
    }

    private func card(titleKey: String, value: String, ratio: Double?, footer: String?) -> NSView {
        let columnWidth = (panelWidth - 24 - CursorDashboardTheme.gridGap) / 2
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true

        let box = NSBox()
        box.titlePosition = .noTitle
        box.boxType = .custom
        box.cornerRadius = CursorDashboardTheme.cardCorner
        box.borderWidth = 1
        box.borderColor = CursorDashboardTheme.cardBorder
        box.fillColor = CursorDashboardTheme.cardFill
        box.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(box)

        let v = NSStackView()
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false

        let t = NSTextField(labelWithString: NSLocalizedString(titleKey, comment: ""))
        t.font = .systemFont(ofSize: 11, weight: .medium)
        t.textColor = CursorDashboardTheme.muted
        let val = NSTextField(labelWithString: value)
        val.font = .systemFont(ofSize: 22, weight: .semibold)
        v.addArrangedSubview(t)
        v.addArrangedSubview(val)
        if let ratio {
            v.addArrangedSubview(DashboardProgressBar(ratio: ratio / 100))
        }
        if let footer, !footer.isEmpty {
            let foot = NSTextField(labelWithString: footer)
            foot.font = .systemFont(ofSize: 11)
            foot.textColor = CursorDashboardTheme.muted
            foot.lineBreakMode = .byWordWrapping
            foot.maximumNumberOfLines = 2
            foot.preferredMaxLayoutWidth = columnWidth - 28
            v.addArrangedSubview(foot)
        }

        box.contentView = v
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            box.topAnchor.constraint(equalTo: wrapper.topAnchor),
            box.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 14),
            v.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -14),
            v.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 12),
            v.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -12),
        ])
        return wrapper
    }

    @objc private func durationTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < UsageDuration.allCases.count else { return }
        duration = UsageDuration.allCases[idx]
        updateDurationSelection()
        reloadDurationViews()
    }

    private func updateDurationSelection() {
        let selected = UsageDuration.allCases.firstIndex(of: duration) ?? UsageDuration.allCases.count - 1
        for (idx, btn) in durationButtons.enumerated() {
            btn.state = idx == selected ? .on : .off
        }
    }

    private func reloadDurationViews() {
        guard let bundle else { return }
        let stacked = CursorModelBreakdown.dailyStackedTokenSeries(
            events: bundle.events,
            duration: duration,
            resetAt: bundle.snapshot.resetsAt
        )
        chartView.stacked = stacked
        tableView.reloadData()
    }

    private var modelRows: [(model: String, requests: Double, tokens: Int, spendCents: Int)] {
        guard let bundle else { return [] }
        return CursorModelBreakdown.aggregateByModel(
            events: bundle.events,
            dailySpend: bundle.dailySpend,
            duration: duration,
            resetAt: bundle.snapshot.resetsAt
        )
    }
}

extension CursorDashboardMenuView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int { modelRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = modelRows[row]
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(tf)
            c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        let text: String
        switch id.rawValue {
        case "dash.col.requests":
            text = String(format: "%.1f", r.requests)
        case "dash.col.tokens":
            text = formatTokens(r.tokens)
        case "dash.col.spend":
            text = formatDollarsFromCents(r.spendCents)
        default:
            text = r.model
        }
        cell.textField?.stringValue = text
        if id.rawValue != "dash.col.model" {
            cell.textField?.alignment = .right
        } else {
            cell.textField?.alignment = .left
        }
        return cell
    }
}

private final class DashboardProgressBar: NSView {
    var ratio: Double
    init(ratio: Double) {
        self.ratio = ratio
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 4).isActive = true
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        CursorDashboardTheme.barTrack.setFill()
        track.fill()
        let w = bounds.width * CGFloat(min(1, max(0, ratio)))
        if w > 0 {
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 2, yRadius: 2)
            CursorDashboardTheme.barFill.setFill()
            fill.fill()
        }
    }
}

private final class DailyUsageChartView: NSView {
    var stacked: (days: [Date], series: [(model: String, tokensByDay: [Date: Int])]) = ([], []) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        guard !stacked.days.isEmpty else {
            let t = NSLocalizedString("dash.chart.empty", comment: "")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: CursorDashboardTheme.muted,
            ]
            t.draw(in: bounds.insetBy(dx: 8, dy: 24), withAttributes: attrs)
            return
        }

        let legendH: CGFloat = 22
        let chartRect = bounds.insetBy(dx: 4, dy: 0)
        let plot = NSRect(x: chartRect.minX, y: chartRect.minY + legendH, width: chartRect.width, height: chartRect.height - legendH - 4)

        var maxVal = 1
        for day in stacked.days {
            let total = stacked.series.reduce(0) { $0 + ($1.tokensByDay[day] ?? 0) }
            maxVal = max(maxVal, total)
        }

        let count = stacked.days.count
        let barW = plot.width / CGFloat(count)
        for (idx, day) in stacked.days.enumerated() {
            var y: CGFloat = plot.minY
            let x = plot.minX + CGFloat(idx) * barW + 1
            let w = max(1, barW - 2)
            for (sIdx, serie) in stacked.series.enumerated() {
                let tokens = serie.tokensByDay[day] ?? 0
                guard tokens > 0 else { continue }
                let h = plot.height * CGFloat(tokens) / CGFloat(maxVal)
                let rect = NSRect(x: x, y: y, width: w, height: h)
                (sIdx < CursorDashboardTheme.chartColors.count
                    ? CursorDashboardTheme.chartColors[sIdx]
                    : CursorDashboardTheme.chartColors[sIdx % CursorDashboardTheme.chartColors.count]).setFill()
                NSBezierPath(rect: rect).fill()
                y += h
            }
        }

        drawLegend(in: NSRect(x: chartRect.minX, y: chartRect.maxY - legendH, width: chartRect.width, height: legendH))
    }

    private func drawLegend(in rect: NSRect) {
        var x = rect.minX
        let maxW = rect.width
        for (idx, serie) in stacked.series.prefix(6).enumerated() {
            let color = CursorDashboardTheme.chartColors[idx % CursorDashboardTheme.chartColors.count]
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: rect.midY - 3, width: 6, height: 6)).fill()
            x += 8
            let label = serie.model as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: CursorDashboardTheme.muted,
            ]
            let size = label.size(withAttributes: attrs)
            if x + size.width > rect.minX + maxW { break }
            label.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attrs)
            x += size.width + 10
        }
    }
}
