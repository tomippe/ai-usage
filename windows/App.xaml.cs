using System.Windows;
using AIUsage.Windows.Services;

namespace AIUsage.Windows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        Settings.Load();

        if (e.Args.Contains("--claude-statusline", StringComparer.OrdinalIgnoreCase))
        {
            ClaudeUsageClient.ConsumeStatusLineInput();
            Shutdown();
            return;
        }

        base.OnStartup(e);
        WindowsTheme.Apply(this);
        ClaudeUsageClient.InstallStatusLineIfAvailable(Environment.ProcessPath ?? "AIUsage.exe");
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }
}
