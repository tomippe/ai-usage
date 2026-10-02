import Cocoa

enum DisplayCurrency: String, CaseIterable {
    case usd
    case eur
    case jpy
    case gbp
    case cny

    private static let defaultsKey = "jp.tomippe.ai-usage.displayCurrency"

    static func languageDefault() -> DisplayCurrency {
        let lang = Locale.preferredLanguages.first ?? ""
        if lang.hasPrefix("ja") { return .jpy }
        if lang.hasPrefix("zh") { return .cny }
        return .usd
    }

    static var current: DisplayCurrency {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let value = DisplayCurrency(rawValue: raw) {
            return value
        }
        return languageDefault()
    }

    static func setCurrent(_ currency: DisplayCurrency) {
        UserDefaults.standard.set(currency.rawValue, forKey: defaultsKey)
    }

    var menuTitleKey: String {
        switch self {
        case .usd: return "menu.currency.usd"
        case .eur: return "menu.currency.eur"
        case .jpy: return "menu.currency.jpy"
        case .gbp: return "menu.currency.gbp"
        case .cny: return "menu.currency.cny"
        }
    }

    var frankfurterCode: String? {
        switch self {
        case .usd: return nil
        case .eur: return "EUR"
        case .jpy: return "JPY"
        case .gbp: return "GBP"
        case .cny: return "CNY"
        }
    }
}

enum ExchangeRateService {
    private static let cacheTTL: TimeInterval = 6 * 3600
    private(set) static var liveRates: [String: Double] = [:]

    static func setLiveRate(_ rate: Double, for currency: DisplayCurrency) {
        guard let code = currency.frankfurterCode else { return }
        liveRates[code] = rate
    }

    static func effectiveRate(for currency: DisplayCurrency) -> Double? {
        guard currency != .usd else { return 1 }
        guard let code = currency.frankfurterCode else { return nil }
        return liveRates[code] ?? cachedUSD(to: currency)
    }

    static func cachedUSD(to currency: DisplayCurrency) -> Double? {
        guard currency != .usd, let code = currency.frankfurterCode else { return nil }
        let rateKey = "jp.tomippe.ai-usage.usdRate.\(code)"
        let dateKey = "jp.tomippe.ai-usage.usdRateAt.\(code)"
        guard let cachedAt = UserDefaults.standard.object(forKey: dateKey) as? Date,
              Date().timeIntervalSince(cachedAt) < cacheTTL
        else { return nil }
        let rate = UserDefaults.standard.double(forKey: rateKey)
        return rate > 0 ? rate : nil
    }

    /// 非同期。完了前は USD 表示にフォールバックする。
    static func fetchUSD(to currency: DisplayCurrency, completion: @escaping (Double?) -> Void) {
        guard currency != .usd, let code = currency.frankfurterCode else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        if let cached = cachedUSD(to: currency) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=\(code)") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var rate: Double?
            defer { DispatchQueue.main.async { completion(rate) } }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double],
                  let fetched = rates[code]
            else { return }
            rate = fetched
            UserDefaults.standard.set(fetched, forKey: "jp.tomippe.ai-usage.usdRate.\(code)")
            UserDefaults.standard.set(Date(), forKey: "jp.tomippe.ai-usage.usdRateAt.\(code)")
        }.resume()
    }

    static func localAmount(dollars: Double, rate: Double?) -> Int? {
        guard let rate else { return nil }
        return Int((dollars * rate).rounded())
    }
}

enum CurrencyDisplayFormatter {
    static func menuBarOnDemandSuffix(dollars: Double, rate: Double?) -> String {
        let usd = String(format: NSLocalizedString("status.cursor_ondemand_usd", comment: ""), dollars)
        let currency = DisplayCurrency.current
        guard currency != .usd else { return usd }
        guard let rate else { return usd }
        switch currency {
        case .usd:
            return usd
        case .jpy:
            guard let yen = ExchangeRateService.localAmount(dollars: dollars, rate: rate) else { return usd }
            return String(format: NSLocalizedString("status.cursor_ondemand_yen", comment: ""), yen)
        case .cny:
            guard let yuan = ExchangeRateService.localAmount(dollars: dollars, rate: rate) else { return usd }
            return String(format: NSLocalizedString("status.cursor_ondemand_cny", comment: ""), yuan)
        case .eur:
            return String(format: NSLocalizedString("status.cursor_ondemand_eur", comment: ""), dollars * rate)
        case .gbp:
            return String(format: NSLocalizedString("status.cursor_ondemand_gbp", comment: ""), dollars * rate)
        }
    }

    static func detailPrimaryAmount(_ dollars: Double, rate: Double?) -> String {
        let currency = DisplayCurrency.current
        guard currency != .usd, let rate else {
            return String(format: "$%.2f", dollars)
        }
        return primaryPlain(dollars * rate, currency: currency)
    }

    /// 従量カードの大きい行（選択通貨。レート未取得時は USD）。
    static func detailOnDemandPrimaryLine(spend: Double, limit: Double?, rate: Double?) -> String {
        let currency = DisplayCurrency.current
        if currency == .usd || rate == nil {
            if let limit {
                return String(format: "$%.2f / $%.2f", spend, limit)
            }
            return String(format: "$%.2f", spend)
        }
        let convertedSpend = spend * rate!
        if let limit {
            return "\(primaryPlain(convertedSpend, currency: currency)) / \(primaryPlain(limit * rate!, currency: currency))"
        }
        return primaryPlain(convertedSpend, currency: currency)
    }

    /// 従量カードのドル併記行。USD 選択時は nil。
    static func detailOnDemandUsdLine(spend: Double, limit: Double?) -> String? {
        guard DisplayCurrency.current != .usd else { return nil }
        if let limit {
            return String(format: "($%.2f / $%.2f)", spend, limit)
        }
        return String(format: "($%.2f)", spend)
    }

    static func detailSpend(cents: Int, rate: Double?) -> NSAttributedString {
        let dollars = Double(cents) / 100
        let mainFont = NSFont.systemFont(ofSize: 11)
        let mainAttrs: [NSAttributedString.Key: Any] = [
            .font: mainFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let currency = DisplayCurrency.current
        if currency == .usd || rate == nil {
            return NSAttributedString(string: formatDollarsFromCents(cents), attributes: mainAttrs)
        }
        let main = primaryPlain(dollars * rate!, currency: currency)
        let result = NSMutableAttributedString(string: main, attributes: mainAttrs)
        appendUsdSecondary(to: result, spend: dollars, limit: nil)
        return result
    }

    private static func primaryPlain(_ amount: Double, currency: DisplayCurrency) -> String {
        switch currency {
        case .usd:
            return String(format: "$%.2f", amount)
        case .eur:
            return String(format: "€%.2f", amount)
        case .gbp:
            return String(format: "£%.2f", amount)
        case .jpy:
            return String(format: "¥%d", Int(amount.rounded()))
        case .cny:
            return String(format: "%d元", Int(amount.rounded()))
        }
    }

    private static func appendUsdSecondary(to result: NSMutableAttributedString, spend: Double, limit: Double?, lineBreakBefore: Bool = false) {
        let secondary: String
        let lead = lineBreakBefore ? "\n" : " "
        if let limit {
            secondary = String(format: "\(lead)($%.2f / $%.2f)", spend, limit)
        } else {
            secondary = String(format: "\(lead)($%.2f)", spend)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: detailUsdSecondaryColor(),
        ]
        result.append(NSAttributedString(string: secondary, attributes: attrs))
    }

    /// メニュー内カスタム view では secondaryLabelColor が背景と同化することがある。
    private static func detailUsdSecondaryColor() -> NSColor {
        detailUsdSecondaryLabelColor()
    }

    static func detailUsdSecondaryLabelColor() -> NSColor {
        NSColor.labelColor.withAlphaComponent(0.55)
    }
}
