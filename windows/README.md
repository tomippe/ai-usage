# AI Usage for Windows

Windows counterpart to the Mac menu bar app. It uses a small always-on-top WPF window; drag anywhere on the window to move it and right-click anywhere to open the Mac-equivalent menu.

## Source and build requirements

- Windows 10 or 11
- .NET 10 SDK with the Windows Desktop targeting pack
- Project: `AIUsage.Windows.csproj`
- Windows version: `version.txt` (independent from the Mac version)
- Build output: `build/out-win/Release/`（`dotnet build` 既定。実行中の EXE とパスが重ならないよう TFM なしの別フォルダ）
- 単一ファイル portable: `build/exe/x64` / `win-arm64`（`build.ps1` の `dotnet publish`）
- NuGet packages: `Microsoft.Data.Sqlite` and `System.Speech`

Build command for a Windows development machine (not run in this workspace):

```powershell
dotnet build .\windows\AIUsage.Windows.csproj -c Release
```

`AIUsage` を起動したまま同じパスへビルドすると `AIUsage.dll` がロックされ **MSB3027** で失敗します。そのときは別フォルダへ出力してください。

```powershell
$staging = Join-Path $PSScriptRoot "build\out-win-staging\Release"
New-Item -ItemType Directory -Force -Path $staging | Out-Null
dotnet build .\windows\AIUsage.Windows.csproj -c Release "-p:OutputPath=$staging\"
```

The repository's root `build.sh` remains the Mac distribution build. No Windows build or package has been produced yet.

### `build.ps1`（フル／`-Exe`）

既定では **必ずこの順番**: **[1] 実行中の `AIUsage` を終了（プロセスが消えるまで待つ）→ [2] ビルド → [3] `build\exe\x64\AIUsage.exe` を起動**です（UNC ステージドビルドに回す前にも [1] を実行）。CI や手動確認で止めたいときは `-NoStop` と `-NoLaunch` を付けます。

```powershell
cd windows
.\build.ps1 -Exe              # portable のみ + 終了・起動（既定）
.\build.ps1                   # MSIX バンドルまで + 同じく終了・起動
.\build.ps1 -Exe -NoStop -NoLaunch
```

## Behavior

- Shows the current or last-active provider's usage, matching the compact Mac menu bar text.
- Detects Cursor and ChatGPT/Codex foreground windows, then keeps the last supported provider selected when another app is focused.
- Reads Cursor auth from `%APPDATA%\Cursor\User\globalStorage\state.vscdb` and calls the same Cursor usage endpoints as the Mac client.
- Reads Codex rate limits from the local `codex app-server` command using read-only, no-approval mode.
- Reads Claude Code's usage statusline file. If Claude Code is installed and no custom `statusLine` is configured, the app creates a PowerShell bridge and registers it without replacing an existing statusline.
- Right-click menu includes provider usage rows, refresh, amount currency, voice thresholds, open at login, About, feedback, update link, restart, and quit.
- Stores display preferences and window position under `%LOCALAPPDATA%\AI Usage\settings.json`. The statusline file stores only quota values and timestamps under `%USERPROFILE%\.claude\ai-usage-rate-limits.json`.

Windows uses the system speech voices. “Check for Updates” opens the project's GitHub Releases page until a Windows updater is added. The Mac Sparkle updater is not included in this project.

## Context menu (Windows 11 style)

Right-click opens a WPF **`ContextMenu`** styled for Windows 11 (rounded card, shadow, Segoe UI Variable, system light/dark via `WindowsTheme`).

## Microsoft Store

See [STORE.md](STORE.md). Listing copy: [docs/store-metadata.md](../docs/store-metadata.md). Build: `.\build.ps1` (MSIX bundle under `build/msix/`).
