using AIUsage.Windows.Models;

namespace AIUsage.Windows.Services;

internal sealed class UsageAlertMonitor
{
    private sealed class State(double remaining)
    {
        public double LastRemaining = remaining;
        public HashSet<int> Fired = Settings.VoiceThresholds.Where(t => remaining <= t).ToHashSet();
    }

    private readonly Dictionary<ProviderKind, State> _states = [];

    public int? Observe(ProviderKind provider, double? remaining)
    {
        if (remaining is not { } raw || !double.IsFinite(raw))
        {
            _states.Remove(provider);
            return null;
        }

        var current = Math.Clamp(raw, 0, 100);
        if (!_states.TryGetValue(provider, out var state))
        {
            _states[provider] = new State(current);
            return null;
        }

        if (current > state.LastRemaining)
        {
            foreach (var threshold in Settings.VoiceThresholds.Where(t => current >= t + 5))
                state.Fired.Remove(threshold);
        }

        var newlyCrossed = new List<int>();
        if (current < state.LastRemaining)
        {
            foreach (var threshold in Settings.VoiceThresholds)
            {
                if (state.LastRemaining > threshold && current <= threshold && state.Fired.Add(threshold)
                    && Settings.IsThresholdEnabled(threshold)) newlyCrossed.Add(threshold);
            }
        }

        state.LastRemaining = current;
        return newlyCrossed.Count == 0 ? null : newlyCrossed.Min();
    }
}

internal sealed class WindowsUsageSpeechAnnouncer : IDisposable
{
    private readonly System.Speech.Synthesis.SpeechSynthesizer _announcer = new();
    private readonly System.Speech.Synthesis.SpeechSynthesizer _preview = new();

    public void Announce(ProviderKind provider, int threshold) => _announcer.SpeakAsync(Phrase(provider, threshold));

    public void Preview(ProviderKind provider, int threshold)
    {
        _preview.SpeakAsyncCancelAll();
        _preview.SpeakAsync(Phrase(provider, threshold));
    }

    public void StopPreview() => _preview.SpeakAsyncCancelAll();

    private static string Phrase(ProviderKind provider, int threshold)
    {
        var providerName = provider switch
        {
            ProviderKind.Cursor => Localizer.Get("cursorSpeech"),
            ProviderKind.Codex => Localizer.Get("codexSpeech"),
            _ => Localizer.Get("claudeSpeech"),
        };
        return Localizer.Get("speech", providerName, threshold);
    }

    public void Dispose()
    {
        _announcer.Dispose();
        _preview.Dispose();
    }
}
