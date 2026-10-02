# プロバイダ

初回は **Cursor と Codex だけ**。Claude は後回し。

未インストールはメニューバーにも一覧にも出さない。

## 前面アプリ → 出す数字

`NSWorkspace.shared.frontmostApplication?.bundleIdentifier`

| bundle id | アプリ | 数字 |
|---|---|---|
| `com.todesktop.230313mzl4w4u92` | Cursor.app | Cursor |
| `com.openai.codex` | ChatGPT.app（署名名 Codex） | Codex |

`CursorWrap.app` はこの開発 Mac にある。実装時に bundle id を見て、Cursor と同じなら Cursor 扱い。

**いずれも前面でないとき（確定）:** 直近でアクティブだったほうの％を出し続ける。消さない。

起動直後でまだどちらも前面になっていないとき: 入っているプロバイダのうち、前回終了時の直近（UserDefaults）。無ければ Cursor 優先、Cursor 未インストールなら Codex。

Terminal で `codex` CLI を動かしているときは前面がターミナルなので、直近のまま。CLI 前面検知は初回はやらない。

前面が切り替わっても、クールダウン中は **取り直さずキャッシュを表示**する。切り替えるのはタイトルの選択だけ。

## Cursor

引き継ぎの本体。詳細は [handoff-from-cursor-usage.md](handoff-from-cursor-usage.md)。

**入っている:** `/Applications/Cursor.app` がある、または

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`

**数字の取り方:** ローカル DB の JWT → cursor.com / api2.cursor.sh。cursor-usage と同一。

**メニューバー:** `totalPercentUsed` があればその％。無ければ `used/limit`。プラン名が取れれば先頭に付ける（`Ultra | 42%`）。

**注意:** Cursor 未ログインだとトークンが無い。一覧には「Cursor・未ログイン」と出す。App Store 版 AI Usage ではこのパスが読めないので直接配布のみ。

## Codex

**入っている:** `/Applications/ChatGPT.app` がある、または `~/.codex/auth.json` がある。

この Mac（2026-10-02）:

- ChatGPT.app の bundle id は `com.openai.codex`
- `~/.codex/auth.json` あり（OAuth: access / refresh / account_id）
- PATH に `codex` コマンドは無いことがある。CLI 必須にしない

**数字の取り方（安定順）**

1. 公式: ローカル `codex app-server` の JSON-RPC
   - `initialize`
   - `account/read`
   - `account/rateLimits/read`
   - 5時間枠（primary）と週間枠（secondary）の `usedPercent` / `resetsAt`、クレジット
   - 起動: `codex -s read-only -a never app-server`（入っているとき）
   - 手順: `initialize` → 応答待ち → `initialized` → `account/rateLimits/read`
2. `~/.codex/auth.json` のトークンで ChatGPT / Codex の使用量 API（CLI が無いとき）。実装時に現行エンドポイントを再確認
3. `/status` の PTY パースは最終手段。初回はやらない

**メニューバー:** 週間％を基本にする（Codex の主制約）。5時間枠は一覧に出す。両方あるときは一覧で並べ、バーは週間（設定で 5h / 低い方、は後から）。

トークンをチャットやログに出さない。`auth.json` は読むだけ。書かない。

## Claude Code

Claude Code の公式statuslineが stdin JSON として渡す `rate_limits.five_hour` / `rate_limits.seven_day` を使用する。Claude Codeが動いて応答を受けたときに値が更新される。バックグラウンドで認証トークンや非公式APIをポーリングしない。

- `~/.claude.json`、`~/.claude/.credentials.json`、またはClaude Code実行ファイルがあるとき一覧に出す
- 初回起動時、既存の `~/.claude/settings.json` に `statusLine` が無い場合だけAI Usageのstatuslineを登録する
- 既存statuslineが設定済みなら変更しない（その場合Claudeの値はstatusline連携されない）
- `~/.claude/ai-usage-rate-limits.json` には利用率・リセット時刻・取得時刻だけを保存し、セッションID、会話、作業パスは保存しない
- Claude Codeを起動した直後でまだ応答が無い場合は利用率が無く、取得待ちを表示する

## 競合

[CodexBar](https://github.com/steipete/CodexBar) は Codex / Claude / Cursor などをメニューバーに出す。AI Usage は tomippe 配布・disk-monitor 型・前面で数字を切り替える、が違い。互換や全プロバイダ横断はしない。
