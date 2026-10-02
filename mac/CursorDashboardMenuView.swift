import Cocoa

// 見た目の正本: cursor-usage/media/dashboard/dashboard.css + dashboard.js (PALETTE)
private enum CursorDashboardTheme {
    static let cardFill = NSColor.windowBackgroundColor
    static let cardBorder = NSColor.separatorColor.withAlphaComponent(0.12)
    static let barTrack = NSColor.labelColor.withAlphaComponent(0.08)
    static var barFill: NSColor { NSColor.controlAccentColor }
    static let muted = NSColor.secondaryLabelColor
    static let chartGrid = NSColor.separatorColor.withAlphaComponent(0.12)
    /// サマリーカードの列間・段間（縦横同じ）
    static let gridGap: CGFloat = 8
    /// 4カードブロックと期間ボタン行の間
    static let cardsToDurationGap: CGFloat = 14
    static let summaryCardHeight: CGFloat = 76
    static let summaryCardColumnRatioLeft: CGFloat = 0.7
    static let summaryCardColumnRatioRight: CGFloat = 0.3
    static let cardCorner: CGFloat = 8
    static let horizontalInset: CGFloat = 12

    static let tableColumns: [(key: String, width: CGFloat)] = [
        ("dash.col.model", 210),
        ("dash.col.requests", 88),
        ("dash.col.tokens", 88),
        ("dash.col.spend", 72),
    ]

    static var panelWidth: CGFloat {
        tableColumns.reduce(0) { $0 + $1.1 } + horizontalInset * 2
    }

    static func summaryCardLeftColumnWidth(contentWidth: CGFloat) -> CGFloat {
        (contentWidth - gridGap) * summaryCardColumnRatioLeft
    }

    static func summaryCardRightColumnWidth(contentWidth: CGFloat) -> CGFloat {
        (contentWidth - gridGap) * summaryCardColumnRatioRight
    }

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

/// カード1枚（NSBox + contentView 制約は NSMenu 内で高さ0に潰れるため使わない）
private final class SummaryCardView: NSView {
    private let stack = NSStackView()

    init(title: String, value: String, valueUsdSecondary: String? = nil, ratio: Double?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = CursorDashboardTheme.cardFill.cgColor
        layer?.cornerRadius = CursorDashboardTheme.cardCorner
        layer?.borderWidth = 1
        layer?.borderColor = CursorDashboardTheme.cardBorder.cgColor

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        addCardRow(cardLabel(title, font: .systemFont(ofSize: 11, weight: .medium), color: CursorDashboardTheme.muted))
        if let valueUsdSecondary, !valueUsdSecondary.isEmpty {
            addCardRow(valueRow(main: value, usdSecondary: valueUsdSecondary))
        } else {
            addCardRow(cardLabel(value, font: .systemFont(ofSize: 22, weight: .semibold), color: .labelColor))
        }
        if let ratio {
            addCardRow(DashboardProgressBar(ratio: ratio / 100))
        } else {
            addCardRow(DashboardProgressBar(ratio: 0))
        }

        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: CursorDashboardTheme.summaryCardHeight),
        ])
    }

    /// 選択通貨の右にドル併記（1行）。
    private func valueRow(main: String, usdSecondary: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 5
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false

        let mainField = cardLabel(main, font: .systemFont(ofSize: 22, weight: .semibold), color: .labelColor)
        mainField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mainField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        mainField.lineBreakMode = .byTruncatingTail
        mainField.maximumNumberOfLines = 1
        mainField.cell?.truncatesLastVisibleLine = true
        if let cell = mainField.cell as? NSTextFieldCell {
            cell.truncatesLastVisibleLine = true
        }

        let usdField = cardLabel(
            usdSecondary,
            font: .systemFont(ofSize: 13, weight: .regular),
            color: CurrencyDisplayFormatter.detailUsdSecondaryLabelColor()
        )
        usdField.setContentHuggingPriority(.required, for: .horizontal)
        usdField.setContentCompressionResistancePriority(.required, for: .horizontal)
        usdField.lineBreakMode = .byClipping
        usdField.maximumNumberOfLines = 1

        row.addArrangedSubview(mainField)
        row.addArrangedSubview(usdField)
        return row
    }

    private func addCardRow(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func cardLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .left
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        field.drawsBackground = false
        if let cell = field.cell as? NSTextFieldCell {
            cell.alignment = .left
        }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

final class CursorDashboardMenuView: NSView {
    private var panelWidth: CGFloat { CursorDashboardTheme.panelWidth }
    private let stack = NSStackView()
    private let cardsBlock = NSStackView()
    private let cardsColLeft = NSStackView()
    private let cardsColRight = NSStackView()
    private let durationRow = NSStackView()
    private let resetHeaderLabel = NSTextField(labelWithString: "")
    private var durationButtons: [NSButton] = []
    private let chartView = DailyUsageChartView()
    private let tableScroll = NSScrollView()
    private let tableView = NSTableView()
    private var bundle: CursorDashboardBundle?
    private var duration: UsageDuration = .billingCycle
    private var layoutContentHeight: CGFloat = 420

    override var intrinsicContentSize: NSSize {
        NSSize(width: panelWidth, height: max(layoutContentHeight, 400))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDurationSelection()
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: CursorDashboardTheme.panelWidth, height: 420))
        translatesAutoresizingMaskIntoConstraints = false
        autoresizingMask = [.maxXMargin]
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let contentWidth = panelWidth - CursorDashboardTheme.horizontalInset * 2

        configureSectionHeading(resetHeaderLabel, size: 12)
        stack.addArrangedSubview(leadingHeadingRow(resetHeaderLabel))

        cardsBlock.orientation = .horizontal
        cardsBlock.spacing = CursorDashboardTheme.gridGap
        cardsBlock.alignment = .top
        cardsBlock.distribution = .fill
        cardsColLeft.orientation = .vertical
        cardsColLeft.spacing = CursorDashboardTheme.gridGap
        cardsColLeft.alignment = .leading
        cardsColLeft.distribution = .fill
        cardsColLeft.translatesAutoresizingMaskIntoConstraints = false
        cardsColLeft.widthAnchor.constraint(
            equalToConstant: summaryCardLeftColumnWidth(contentWidth: contentWidth)
        ).isActive = true
        cardsColRight.orientation = .vertical
        cardsColRight.spacing = CursorDashboardTheme.gridGap
        cardsColRight.alignment = .leading
        cardsColRight.distribution = .fill
        cardsColRight.translatesAutoresizingMaskIntoConstraints = false
        cardsColRight.widthAnchor.constraint(
            equalToConstant: CursorDashboardTheme.summaryCardRightColumnWidth(contentWidth: contentWidth)
        ).isActive = true
        cardsBlock.addArrangedSubview(cardsColLeft)
        cardsBlock.addArrangedSubview(cardsColRight)
        let cardsWrapper = fullWidthBlock(cardsBlock)
        stack.addArrangedSubview(cardsWrapper)

        durationRow.orientation = .horizontal
        durationRow.spacing = 4
        durationRow.distribution = .fillEqually
        durationRow.translatesAutoresizingMaskIntoConstraints = false
        for (idx, dur) in UsageDuration.allCases.enumerated() {
            let btn = NSButton(title: NSLocalizedString(dur.menuLabelKey, comment: ""), target: self, action: #selector(durationTapped(_:)))
            btn.tag = idx
            btn.setButtonType(.toggle)
            btn.bezelStyle = .accessoryBarAction
            btn.font = .systemFont(ofSize: 11, weight: .medium)
            btn.controlSize = .small
            btn.wantsLayer = true
            durationButtons.append(btn)
            durationRow.addArrangedSubview(btn)
        }
        let durationWrapper = fullWidthBlock(durationRow)
        stack.addArrangedSubview(durationWrapper)
        stack.setCustomSpacing(CursorDashboardTheme.cardsToDurationGap, after: cardsWrapper)
        updateDurationSelection()

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 168).isActive = true
        stack.addArrangedSubview(fullWidthBlock(chartView))

        let modelTitle = NSTextField(labelWithString: NSLocalizedString("dash.models", comment: ""))
        configureSectionHeading(modelTitle, size: 13, weight: .medium)
        stack.addArrangedSubview(leadingHeadingRow(modelTitle))

        tableView.headerView = NSTableHeaderView()
        for col in CursorDashboardTheme.tableColumns {
            tableView.addTableColumn(makeColumn(col.key, col.width))
        }
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.rowHeight = 18
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.drawsBackground = false
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        stack.addArrangedSubview(fullWidthBlock(tableScroll))

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: panelWidth),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CursorDashboardTheme.horizontalInset),
            stack.widthAnchor.constraint(equalToConstant: contentWidth),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        for row in stack.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func refreshMenuLayoutSize() {
        layoutSubtreeIfNeeded()
        layoutContentHeight = max(stack.fittingSize.height + 10, 400)
        invalidateIntrinsicContentSize()
        setFrameSize(NSSize(width: panelWidth, height: layoutContentHeight))
    }

    private func configureSectionHeading(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight = .medium) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let cell = label.cell as? NSTextFieldCell {
            cell.alignment = .left
        }
    }

    /// 幅いっぱいのブロックを左端に固定（NSMenu の view が横に広いとき右寄せに見えるのを防ぐ）。
    private func fullWidthBlock(_ content: NSView) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    /// NSStackView(.width) だとラベルだけ右寄せに見えるため、行コンテナで左端に固定する。
    private func leadingHeadingRow(_ label: NSTextField) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    private func makeColumn(_ key: String, _ w: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
        col.title = NSLocalizedString(key, comment: "")
        col.width = w
        col.minWidth = w
        col.maxWidth = w
        if key != "dash.col.model" {
            col.headerCell.alignment = .right
        } else {
            col.headerCell.alignment = .left
        }
        return col
    }

    func update(bundle: CursorDashboardBundle) {
        self.bundle = bundle
        updateResetHeader(resetAt: bundle.snapshot.resetsAt)
        rebuildCards(snapshot: bundle.snapshot)
        reloadDurationViews()
        refreshMenuLayoutSize()
    }

    private func updateResetHeader(resetAt: Date?) {
        guard let resetAt else {
            resetHeaderLabel.stringValue = ""
            resetHeaderLabel.isHidden = true
            return
        }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "yyyy/MM/dd HH:mm"
        resetHeaderLabel.stringValue = String(
            format: NSLocalizedString("dash.reset_header", comment: ""),
            f.string(from: resetAt)
        )
        resetHeaderLabel.isHidden = false
    }

    private func summaryCardLeftColumnWidth(contentWidth: CGFloat) -> CGFloat {
        CursorDashboardTheme.summaryCardLeftColumnWidth(contentWidth: contentWidth)
    }

    private func clearCardColumns() {
        for col in [cardsColLeft, cardsColRight] {
            for view in col.arrangedSubviews {
                col.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
    }

    private func rebuildCards(snapshot: CursorUsageSnapshot) {
        clearCardColumns()
        if let err = snapshot.errorMessage {
            let msg = NSLocalizedString(err == "not_logged_in" ? "status.not_logged_in" : "status.unavailable", comment: "")
            addCard(to: cardsColLeft, SummaryCardView(title: NSLocalizedString("status.unavailable", comment: ""), value: msg, ratio: nil))
            return
        }

        addCard(to: cardsColLeft, SummaryCardView(
            title: NSLocalizedString("dash.card.total", comment: ""),
            value: formatPercent(snapshot.totalPercentUsed ?? 0),
            ratio: snapshot.totalPercentUsed
        ))
        addCard(to: cardsColRight, SummaryCardView(
            title: NSLocalizedString("dash.card.auto", comment: ""),
            value: formatPercent(snapshot.autoPercentUsed ?? 0),
            ratio: snapshot.autoPercentUsed
        ))
        if snapshot.onDemand == .disabled {
            addCard(to: cardsColLeft, SummaryCardView(
                title: NSLocalizedString("dash.card.ondemand", comment: ""),
                value: "—",
                ratio: nil
            ))
        } else {
            let onDemandLimit = snapshot.onDemand == .limited ? snapshot.onDemandLimitDollars : nil
            let rate = ExchangeRateService.effectiveRate(for: DisplayCurrency.current)
            let spend = snapshot.onDemandSpendDollars
            addCard(to: cardsColLeft, SummaryCardView(
                title: NSLocalizedString("dash.card.ondemand", comment: ""),
                value: CurrencyDisplayFormatter.detailOnDemandPrimaryLine(
                    spend: spend,
                    limit: onDemandLimit,
                    rate: rate
                ),
                valueUsdSecondary: rate != nil
                    ? CurrencyDisplayFormatter.detailOnDemandUsdLine(spend: spend, limit: onDemandLimit)
                    : nil,
                ratio: onDemandRatio(snapshot)
            ))
        }
        addCard(to: cardsColRight, SummaryCardView(
            title: NSLocalizedString("dash.card.api", comment: ""),
            value: formatPercent(snapshot.apiPercentUsed ?? 0),
            ratio: snapshot.apiPercentUsed
        ))
    }

    private func addCard(to column: NSStackView, _ card: SummaryCardView) {
        column.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }

    private func onDemandRatio(_ s: CursorUsageSnapshot) -> Double? {
        guard s.onDemand == .limited, let limit = s.onDemandLimitDollars, limit > 0 else { return nil }
        return min(100, s.onDemandSpendDollars / limit * 100)
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
            styleDurationButton(btn, selected: idx == selected)
        }
    }

    private func styleDurationButton(_ btn: NSButton, selected: Bool) {
        btn.state = selected ? .on : .off
        btn.layer?.cornerRadius = 6
        btn.layer?.cornerCurve = .continuous
        let font = btn.font ?? NSFont.systemFont(ofSize: 11, weight: .medium)
        if selected {
            btn.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            btn.attributedTitle = NSAttributedString(
                string: btn.title,
                attributes: [.foregroundColor: NSColor.white, .font: font]
            )
        } else {
            btn.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
            btn.attributedTitle = NSAttributedString(
                string: btn.title,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]
            )
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
            let rate = ExchangeRateService.effectiveRate(for: DisplayCurrency.current)
            cell.textField?.attributedStringValue = CurrencyDisplayFormatter.detailSpend(cents: r.spendCents, rate: rate)
            cell.textField?.alignment = .right
            return cell
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

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
    private static let yAxisWidth: CGFloat = 42
    private static let xAxisHeight: CGFloat = 16
    private static let legendHeight: CGFloat = 38

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
            let para = NSMutableParagraphStyle()
            para.alignment = .left
            var emptyAttrs = attrs
            emptyAttrs[.paragraphStyle] = para
            t.draw(in: bounds.insetBy(dx: 8, dy: 24), withAttributes: emptyAttrs)
            return
        }

        let chartRect = bounds.insetBy(dx: 4, dy: 0)
        let plot = NSRect(
            x: chartRect.minX + Self.yAxisWidth,
            y: chartRect.minY + Self.legendHeight + Self.xAxisHeight + 2,
            width: chartRect.width - Self.yAxisWidth - 2,
            height: chartRect.height - Self.legendHeight - Self.xAxisHeight - 6
        )

        var dataMax = 1
        for day in stacked.days {
            let total = stacked.series.reduce(0) { $0 + ($1.tokensByDay[day] ?? 0) }
            dataMax = max(dataMax, total)
        }
        let axisMax = niceAxisMaximum(for: dataMax)
        let yTicks = yAxisTickValues(maximum: axisMax)

        drawYAxisGrid(ticks: yTicks, axisMax: axisMax, plot: plot)
        drawXAxisLabels(days: stacked.days, plot: plot)

        let count = stacked.days.count
        let barW = plot.width / CGFloat(count)
        for (idx, day) in stacked.days.enumerated() {
            var y: CGFloat = plot.minY
            let x = plot.minX + CGFloat(idx) * barW + 1
            let w = max(1, barW - 2)
            for (sIdx, serie) in stacked.series.enumerated() {
                let tokens = serie.tokensByDay[day] ?? 0
                guard tokens > 0 else { continue }
                let h = plot.height * CGFloat(tokens) / CGFloat(axisMax)
                let rect = NSRect(x: x, y: y, width: w, height: h)
                (sIdx < CursorDashboardTheme.chartColors.count
                    ? CursorDashboardTheme.chartColors[sIdx]
                    : CursorDashboardTheme.chartColors[sIdx % CursorDashboardTheme.chartColors.count]).setFill()
                NSBezierPath(rect: rect).fill()
                y += h
            }
        }

        drawLegend(in: NSRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: Self.legendHeight))
    }

    private func drawYAxisGrid(ticks: [Int], axisMax: Int, plot: NSRect) {
        let gridColor = CursorDashboardTheme.chartGrid
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: CursorDashboardTheme.muted,
        ]
        let labelWidth = Self.yAxisWidth - 6
        let labelBox = NSRect(x: plot.minX - Self.yAxisWidth, y: 0, width: labelWidth, height: 12)

        for tick in ticks {
            let ratio = axisMax > 0 ? CGFloat(tick) / CGFloat(axisMax) : 0
            let y = plot.minY + plot.height * ratio
            gridColor.setStroke()
            let line = NSBezierPath()
            line.lineWidth = 0.5
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            line.stroke()

            let label = formatChartAxisTokens(tick) as NSString
            let size = label.size(withAttributes: labelAttrs)
            var box = labelBox
            box.origin.y = y - size.height / 2
            let para = NSMutableParagraphStyle()
            para.alignment = .right
            var attrs = labelAttrs
            attrs[.paragraphStyle] = para
            label.draw(in: box, withAttributes: attrs)
        }
    }

    private func drawXAxisLabels(days: [Date], plot: NSRect) {
        guard !days.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: CursorDashboardTheme.muted,
        ]
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "M/d"

        let count = days.count
        let barW = plot.width / CGFloat(count)
        let indices = xLabelDayIndices(dayCount: count)

        for idx in indices {
            let day = days[idx]
            let label = df.string(from: day) as NSString
            let size = label.size(withAttributes: attrs)
            let centerX = plot.minX + (CGFloat(idx) + 0.5) * barW
            let x = centerX - size.width / 2
            let y = plot.minY - Self.xAxisHeight + 1
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    /// VS ダッシュボードに近い 0 … N 刻み（例: 0, 100M, 200M, …）。
    private func niceAxisMaximum(for dataMax: Int) -> Int {
        guard dataMax > 0 else { return 1 }
        let intervalCount = 5
        let rawStep = Double(dataMax) / Double(intervalCount)
        let magnitude = pow(10, floor(log10(max(rawStep, 1))))
        let normalized = rawStep / magnitude
        let niceNormalized: Double
        if normalized <= 1 { niceNormalized = 1 }
        else if normalized <= 2 { niceNormalized = 2 }
        else if normalized <= 5 { niceNormalized = 5 }
        else { niceNormalized = 10 }
        let step = max(1, Int(niceNormalized * magnitude))
        var niceMax = step * intervalCount
        if niceMax < dataMax {
            niceMax = step * (intervalCount + 1)
        }
        return niceMax
    }

    private func yAxisTickValues(maximum: Int) -> [Int] {
        guard maximum > 0 else { return [0] }
        let intervalCount = 5
        let step = max(1, maximum / intervalCount)
        return (0...intervalCount).map { $0 * step }
    }

    private func xLabelDayIndices(dayCount: Int) -> [Int] {
        guard dayCount > 0 else { return [] }
        if dayCount == 1 { return [0] }
        let maxLabels = 8
        if dayCount <= maxLabels {
            return Array(0..<dayCount)
        }
        var indices: [Int] = [0]
        var idx = 0
        let minGap = max(3, dayCount / (maxLabels - 1))
        while idx + minGap < dayCount - 1 {
            idx += minGap
            indices.append(idx)
        }
        if indices.last != dayCount - 1 {
            indices.append(dayCount - 1)
        }
        return indices
    }

    private func formatChartAxisTokens(_ n: Int) -> String {
        if n == 0 { return "0" }
        let v = Double(n)
        if v >= 1_000_000_000 {
            let x = v / 1_000_000_000
            return x.truncatingRemainder(dividingBy: 1) < 0.001 ? String(format: "%.0fB", x) : String(format: "%.1fB", x)
        }
        if v >= 1_000_000 {
            let x = v / 1_000_000
            return x.truncatingRemainder(dividingBy: 1) < 0.001 ? String(format: "%.0fM", x) : String(format: "%.1fM", x)
        }
        if v >= 1_000 {
            let x = v / 1_000
            return x.truncatingRemainder(dividingBy: 1) < 0.001 ? String(format: "%.0fK", x) : String(format: "%.1fK", x)
        }
        return "\(n)"
    }

    private func drawLegend(in rect: NSRect) {
        var x = rect.minX
        var baselineY = rect.maxY - 10
        let lineStep: CGFloat = 13
        let maxX = rect.minX + rect.width
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: CursorDashboardTheme.muted,
        ]
        for (idx, serie) in stacked.series.prefix(10).enumerated() {
            let color = CursorDashboardTheme.chartColors[idx % CursorDashboardTheme.chartColors.count]
            let label = serie.model as NSString
            let size = label.size(withAttributes: attrs)
            let itemW = 8 + size.width + 10
            if x + itemW > maxX, x > rect.minX {
                x = rect.minX
                baselineY -= lineStep
            }
            if baselineY < rect.minY + 4 { break }
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: baselineY - 3, width: 6, height: 6)).fill()
            label.draw(at: NSPoint(x: x + 8, y: baselineY - size.height / 2), withAttributes: attrs)
            x += itemW
        }
    }
}
