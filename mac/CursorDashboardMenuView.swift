import Cocoa

final class CursorDashboardMenuView: NSView {
    private let width: CGFloat = 380
    private let stack = NSStackView()
    private let cardsStack = NSGridView()
    private let resetLabel = NSTextField(labelWithString: "")
    private let durationControl = NSSegmentedControl()
    private let chartView = DailyUsageChartView()
    private let tableScroll = NSScrollView()
    private let tableView = NSTableView()
    private var bundle: CursorDashboardBundle?
    private var duration: UsageDuration = .billingCycle

    override var intrinsicContentSize: NSSize {
        NSSize(width: width, height: 460)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 460))
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let title = NSTextField(labelWithString: NSLocalizedString("dash.title", comment: ""))
        title.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(title)

        cardsStack.rowSpacing = 6
        cardsStack.columnSpacing = 8
        stack.addArrangedSubview(cardsStack)

        resetLabel.font = .systemFont(ofSize: 11)
        resetLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(resetLabel)

        durationControl.segmentCount = UsageDuration.allCases.count
        for (idx, dur) in UsageDuration.allCases.enumerated() {
            durationControl.setLabel(NSLocalizedString(dur.menuLabelKey, comment: ""), forSegment: idx)
        }
        durationControl.selectedSegment = UsageDuration.allCases.count - 1
        durationControl.target = self
        durationControl.action = #selector(durationChanged)
        durationControl.segmentDistribution = .fillEqually
        stack.addArrangedSubview(durationControl)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 120).isActive = true
        stack.addArrangedSubview(chartView)

        let modelTitle = NSTextField(labelWithString: NSLocalizedString("dash.models", comment: ""))
        modelTitle.font = .boldSystemFont(ofSize: 12)
        stack.addArrangedSubview(modelTitle)

        tableView.headerView = NSTableHeaderView()
        tableView.addTableColumn(makeColumn("dash.col.model", 160))
        tableView.addTableColumn(makeColumn("dash.col.requests", 60))
        tableView.addTableColumn(makeColumn("dash.col.tokens", 70))
        tableView.addTableColumn(makeColumn("dash.col.spend", 60))
        tableView.rowHeight = 18
        tableView.delegate = self
        tableView.dataSource = self
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        stack.addArrangedSubview(tableScroll)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
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

    private func rebuildCards(snapshot: CursorUsageSnapshot) {
        cardsStack.subviews.forEach { $0.removeFromSuperview() }
        if let err = snapshot.errorMessage {
            cardsStack.addRow(with: [card(titleKey: "status.unavailable", value: NSLocalizedString(err == "not_logged_in" ? "status.not_logged_in" : "status.unavailable", comment: ""), ratio: nil)])
            return
        }
        cardsStack.addRow(with: [
            card(titleKey: "dash.card.total", value: formatPercent(snapshot.totalPercentUsed ?? 0), ratio: snapshot.totalPercentUsed),
            card(titleKey: "dash.card.auto", value: formatPercent(snapshot.autoPercentUsed ?? 0), ratio: snapshot.autoPercentUsed),
        ])
        cardsStack.addRow(with: [
            card(titleKey: "dash.card.api", value: formatPercent(snapshot.apiPercentUsed ?? 0), ratio: snapshot.apiPercentUsed),
            card(titleKey: "dash.card.ondemand", value: onDemandText(snapshot), ratio: onDemandRatio(snapshot)),
        ])
        if let reset = snapshot.resetsAt {
            let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: reset).day ?? 0)
            let df = DateFormatter()
            df.dateStyle = .medium
            resetLabel.stringValue = String(
                format: NSLocalizedString("dash.reset", comment: ""),
                df.string(from: reset),
                days
            )
        } else {
            resetLabel.stringValue = ""
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

    private func card(titleKey: String, value: String, ratio: Double?) -> NSView {
        let box = NSBox()
        box.titlePosition = .noTitle
        box.boxType = .custom
        box.cornerRadius = 6
        box.borderWidth = 1
        box.fillColor = NSColor.controlBackgroundColor
        let v = NSStackView()
        v.orientation = .vertical
        v.spacing = 4
        let t = NSTextField(labelWithString: NSLocalizedString(titleKey, comment: ""))
        t.font = .systemFont(ofSize: 10)
        t.textColor = .secondaryLabelColor
        let val = NSTextField(labelWithString: value)
        val.font = .boldSystemFont(ofSize: 14)
        v.addArrangedSubview(t)
        v.addArrangedSubview(val)
        if let ratio {
            v.addArrangedSubview(ProgressBarView(ratio: ratio / 100))
        }
        box.contentView = v
        box.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return box
    }

    @objc private func durationChanged() {
        let idx = durationControl.selectedSegment
        guard idx >= 0, idx < UsageDuration.allCases.count else { return }
        duration = UsageDuration.allCases[idx]
        reloadDurationViews()
    }

    private func reloadDurationViews() {
        guard let bundle else { return }
        let series = CursorModelBreakdown.dailyTokenSeries(
            events: bundle.events,
            duration: duration,
            resetAt: bundle.snapshot.resetsAt
        )
        chartView.points = series
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
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
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
        return cell
    }
}

private final class ProgressBarView: NSView {
    var ratio: Double
    init(ratio: Double) {
        self.ratio = ratio
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        NSColor.separatorColor.setFill()
        track.fill()
        let w = bounds.width * CGFloat(min(1, max(0, ratio)))
        if w > 0 {
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: 3, yRadius: 3)
            NSColor.controlAccentColor.setFill()
            fill.fill()
        }
    }
}

private final class DailyUsageChartView: NSView {
    var points: [(day: Date, totalTokens: Int)] = [] {
        didSet { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard !points.isEmpty else {
            let t = NSLocalizedString("dash.chart.empty", comment: "")
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            t.draw(in: bounds.insetBy(dx: 8, dy: 8), withAttributes: attrs)
            return
        }
        let maxVal = max(1, points.map(\.totalTokens).max() ?? 1)
        let barW = bounds.width / CGFloat(points.count)
        for (idx, p) in points.enumerated() {
            let h = bounds.height * 0.85 * CGFloat(p.totalTokens) / CGFloat(maxVal)
            let rect = NSRect(x: CGFloat(idx) * barW + 1, y: 0, width: max(1, barW - 2), height: h)
            NSColor.controlAccentColor.withAlphaComponent(0.75).setFill()
            NSBezierPath(rect: rect).fill()
        }
    }
}
