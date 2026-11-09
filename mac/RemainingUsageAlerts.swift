import Foundation

struct UsageThresholdAlert {
    let provider: ProviderKind
    let window: UsageAlertWindow
    let thresholdPercent: Int
}

enum UsageAlertWindow: String, Hashable {
    case standard
    case cursorNative
    case cursorAPI
    case fiveHour
    case weekly

    var speechNameKey: String { "speech.window.\(rawValue)" }
}

protocol UsageThresholdAnnouncing {
    func announce(_ alert: UsageThresholdAlert)
    func preview(_ alert: UsageThresholdAlert)
    func stopPreview()
}

/// Platform-independent threshold tracking. UI and speech engines live in platform adapters.
struct RemainingUsageAlertMonitor {
    static let supportedThresholds = [50, 40, 30, 20, 10, 5, 0]

    private struct ProviderState {
        var lastRemainingPercent: Double
        var firedThresholds: Set<Int>
    }

    private var states: [String: ProviderState] = [:]

    mutating func observe(
        provider: ProviderKind,
        window: UsageAlertWindow = .standard,
        remainingPercent: Double?,
        enabledThresholds: Set<Int>
    ) -> UsageThresholdAlert? {
        let stateKey = "\(provider.rawValue):\(window.rawValue)"
        guard let remainingPercent, remainingPercent.isFinite else {
            states.removeValue(forKey: stateKey)
            return nil
        }

        let current = max(0, min(100, remainingPercent))
        let thresholds = Set(Self.supportedThresholds)

        guard var state = states[stateKey] else {
            states[stateKey] = ProviderState(
                lastRemainingPercent: current,
                firedThresholds: Set(Self.supportedThresholds.filter { current <= Double($0) })
            )
            return nil
        }

        if current > state.lastRemainingPercent {
            for threshold in thresholds where current >= Double(threshold + 5) {
                state.firedThresholds.remove(threshold)
            }
        }

        var newlyCrossedEnabledThresholds: [Int] = []
        if current < state.lastRemainingPercent {
            for threshold in thresholds
            where state.lastRemainingPercent > Double(threshold)
                && current <= Double(threshold)
                && !state.firedThresholds.contains(threshold) {
                state.firedThresholds.insert(threshold)
                if enabledThresholds.contains(threshold) {
                    newlyCrossedEnabledThresholds.append(threshold)
                }
            }
        }

        state.lastRemainingPercent = current
        states[stateKey] = state

        // A single poll may skip several levels. Announce only the lowest newly crossed level.
        guard let threshold = newlyCrossedEnabledThresholds.min() else { return nil }
        return UsageThresholdAlert(provider: provider, window: window, thresholdPercent: threshold)
    }
}
