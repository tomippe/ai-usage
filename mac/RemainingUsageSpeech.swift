import AVFoundation
import Foundation

final class MacUsageSpeechAnnouncer: UsageThresholdAnnouncing {
    private let alertSynthesizer = AVSpeechSynthesizer()
    private let previewSynthesizer = AVSpeechSynthesizer()

    func announce(_ alert: UsageThresholdAlert) {
        alertSynthesizer.speak(utterance(for: alert))
    }

    func preview(_ alert: UsageThresholdAlert) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(utterance(for: alert))
    }

    func stopPreview() {
        previewSynthesizer.stopSpeaking(at: .immediate)
    }

    private func utterance(for alert: UsageThresholdAlert) -> AVSpeechUtterance {
        let phrase = String(
            format: NSLocalizedString("speech.remaining", comment: "Spoken when an app's remaining usage crosses a threshold"),
            NSLocalizedString(alert.provider.speechDisplayNameKey, comment: "Spoken name of an AI provider"),
            NSLocalizedString(alert.window.speechNameKey, comment: "Spoken name of the usage window"),
            alert.thresholdPercent
        )
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.preferredSpeechLanguage)
        return utterance
    }

    private static var preferredSpeechLanguage: String {
        let language = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        if language.hasPrefix("ja") { return "ja-JP" }
        if language.hasPrefix("zh") { return "zh-CN" }
        if language.hasPrefix("en") { return "en-US" }
        return language
    }
}
