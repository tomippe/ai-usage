# Microsoft Store 申請用メタデータ — AI Usage (Windows)

Partner Center で入力する文言の正本。`Package.appxmanifest` の Identity / Publisher と一致させる。

---

## 基本情報

プライバシーポリシー URL
https://apps.tomippe.jp/ai-usage/policy/

カテゴリ
ユーティリティとツール / Utilities & tools

著作権
Copyright © 2026 tomippe. All rights reserved.

データ収集（個人データ）
いいえ（収集しない）

---

## Product identity

正本: windows/Package.appxmanifest

Package/Identity/Name
StudioTomippe.AIUsageChatGPTClaudeCursorMonitor

Package/Identity/Publisher
CN=7AA9757D-D72F-4DE2-9980-F9A659207C27

Package/Properties/DisplayName
AI Usage: ChatGPT, Claude, Cursor Monitor

Package/Properties/PublisherDisplayName
Studio Tomippe

Store URL
https://apps.microsoft.com/detail/9n4c1p9hz3vv?hl=ja-JP&gl=JP

Store ID
9N4C1P9HZ3VV（.env の MS_STORE_PRODUCT_ID と一致）

Identity Version
version.txt の a.b.c → a.b.c.0（第4桁は常に 0）

提出パッケージ
windows/build/msix/AIUsage.msixbundle

---

## Partner Center リスト登録（3言語）

### アプリ名（Product name）

日本語
AI Usage

英語
AI Usage

簡体中国语
AI Usage

### 短い説明（Short description）

日本語
Cursor と ChatGPT の AI 使用率を、常に前面のコンパクトなウィンドウで表示します。

英語
See Cursor and ChatGPT AI usage in a small always-on-top window.

簡体中国语
在置顶小窗口中查看 Cursor 与 ChatGPT 的 AI 使用率。

### 説明文（Full description）

日本語
AI Usage は、Cursor と ChatGPT（Codex）の使用率をデスクトップ上でひと目確認できるユーティリティです。

前面アプリに合わせて表示するプロバイダを切り替え、残量・リセット時刻をコンパクトに表示します。Claude Code をお使いの場合は、ステータスライン連携で使用率を読み取れます。

右クリックメニューから更新、通貨表示、音声アラート、ログイン時起動、フィードバックなどを設定できます。

データはお使いの PC 上の Cursor / Codex / Claude の設定・ローカルファイルから読み取るだけで、Studio Tomippe のサーバーへ個人データを送信しません。

英語
AI Usage shows Cursor and ChatGPT (Codex) usage at a glance in a small always-on-top window.

It follows your foreground app to choose the provider and shows remaining quota and reset times. Claude Code users can connect via the status line bridge.

Right-click for refresh, currency, voice alerts, startup options, and feedback.

Usage is read from local Cursor, Codex, and Claude files on your PC. No personal data is sent to Studio Tomippe servers.

簡体中国语
AI Usage 在置顶的紧凑窗口中显示 Cursor 与 ChatGPT（Codex）的使用率。

会根据前台应用切换提供商，并显示剩余额度与重置时间。使用 Claude Code 时可通过状态行桥接读取使用率。

右键菜单可刷新、设置货币与语音提醒、开机启动以及反馈。

仅从本机 Cursor、Codex、Claude 相关文件读取，不向 Studio Tomippe 服务器发送个人数据。

---

## What's new in this version（3言語）

日本語
Windows 版の初回 Store 公開です。

英語
Initial Microsoft Store release for Windows.

簡体中国语
Windows 版首次发布至 Microsoft Store。

---

## Product features（3言語）

日本語
Cursor / ChatGPT 使用率の表示
前面アプリに連動したプロバイダ切替
Claude Code ステータスライン連携
音声アラート
日本語・English・中文 UI

英語
Cursor and ChatGPT usage display
Provider follows foreground app
Claude Code status line bridge
Voice alerts
Japanese, English, and Chinese UI

簡体中国语
显示 Cursor / ChatGPT 使用率
随前台应用切换提供商
Claude Code 状态行桥接
语音提醒
日语、英语、简体中文界面

---

## Notes for Certification

The app is a compact always-on-top WPF desktop utility (runFullTrust). Drag anywhere on the window to move it. Right-click anywhere to open the context menu (Refresh, currency, voice alerts, About, feedback, restart, quit).

### Testing prerequisites (recommended)

Full certification testing assumes the reviewer has the same tools end users would use:

- **Cursor** desktop app installed and **signed in** (usage comes from the local Cursor database and Cursor usage APIs).
- **ChatGPT / Codex** available on the PC (**OpenAI Codex CLI** or the ChatGPT desktop app). The app talks to the local `codex` app-server in read-only mode; the user must be signed in to Codex/ChatGPT for quota text to appear.
- **Claude Code** installed (CLI or desktop) when testing the Claude provider. Usage is read from a JSON snapshot under %USERPROFILE%\.claude\ written by an optional status-line helper the app may register if Claude has no custom statusLine yet.

These products are **not bundled** with AI Usage. If they are missing, the window and menu still work and show localized states such as “Usage unavailable” or “Not signed in”. That is expected and is not a failure of the Store package itself.

### How to verify

1. Install and launch **AI Usage** from the submitted package. A small always-on-top floating window appears (no separate main window).
2. **Right-click** the window. Confirm the menu opens and items respond: **Refresh Now**, currency submenu, voice alerts, About, Send Feedback (opens browser), Check for Updates (opens GitHub releases in browser), Restart, Quit.
3. **Left-drag** the window; position should be remembered after restart.
4. **If Cursor is installed and signed in:** bring Cursor to the foreground or select Cursor in the menu. The floating label should show Cursor usage (percentages / reset hints) or a brief “Loading…” while fetching.
5. **If Codex/ChatGPT is installed and signed in:** focus ChatGPT or Codex-related UI (or open that provider from the menu if offered). Expect ChatGPT/Codex quota text when the local app-server responds.
6. **If Claude Code is installed:** after first run, allow a few seconds for the optional status-line bridge. Focus Claude or open it from the menu; Claude usage may appear once %USERPROFILE%\.claude\ai-usage-rate-limits.json is updated (or “Loading…” / unavailable if Claude is not running).
7. With **no AI tools installed**, confirm the app still launches, shows localized unavailable messaging, and Quit works.

### Data and network

- **No user credentials or usage history are sent to Studio Tomippe servers.**
- Local reads only: Cursor `%APPDATA%\Cursor\User\globalStorage\state.vscdb`, Codex via local CLI, Claude snapshot under `%USERPROFILE%\.claude\`.
- Settings (currency, voice thresholds, window position) under `%LOCALAPPDATA%\AI Usage\settings.json`.
- Internet: Cursor/Codex usage API calls as required by those products, optional FX rates (Frankfurter public API), and user-initiated links (feedback form, update page).

### Capabilities

- **internetClient** — usage and public FX endpoints only.
- **runFullTrust** — desktop WPF app; reads local provider files and invokes local CLI processes; no elevated admin requirement for normal use.

---

## 申請前チェックリスト

- [ ] Partner Center でアプリ作成、Store ID を .env に記録
- [ ] Package.appxmanifest の Publisher が PFX と一致
- [ ] Assets\*.png 生成（generate-assets.ps1）
- [ ] .\build.ps1 で MSIX VERIFY / 署名成功
- [ ] プライバシー URL が公開済み
- [ ] 紹介ページに Windows / Store ボタン（公開後に app-winurl 更新）
