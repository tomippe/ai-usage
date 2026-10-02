# AI Usage 製品仕様

2026-10-02、cursor-usage リポジトリでの会話で決めた内容。

## 名前

| 項目 | 値 |
|---|---|
| 表示名 | **AI Usage** |
| スラッグ | `ai-usage` |
| バンドル ID（案） | `jp.tomippe.ai-usage` |
| 紹介ページ投稿タイトル（案） | `AI Usage by tomippe` |
| 拡張「Cursor Usage」 | 別製品。Open VSX はそのまま |

「LLM Usage」は正確だが、メニューバーと紹介ページでは AI の方が自然、でこれに決めた。既存の Disk Monitor / IP Monitor と同じ短い普通の言葉。

## 何をするか

1. メニューバーに、**いま前面の対応アプリ**の使用量（％）を出す
2. クリックすると、**入っているプロバイダだけ**一覧
3. 入っていないプロバイダはメニューバーにも一覧にも出さない

## メニューバーの切り替え

前面アプリの bundle id で数字を切り替える。

| 前面 | 出す数字 |
|---|---|
| Cursor（`com.todesktop.230313mzl4w4u92`） | Cursor のプラン％ |
| ChatGPT / Codex（`com.openai.codex`。実体は `ChatGPT.app`） | Codex の枠％ |
| それ以外（Finder、ブラウザ、ターミナル等） | **直近でアクティブだったほう** |

2026-10-02 確定: いずれも前面でないときは、最後に前面だった対応アプリの％を出し続ける。消さない。起動直後でまだどちらも前面になっていないときは、入っているプロバイダのうち最後に使った方（不明なら Cursor 優先）。

Terminal で `codex` CLI を動かしているときは前面がターミナルなので、直近アクティブのまま（制限として書いておく）。

`CursorWrap.app` はこの Mac にある。実装時に bundle id を確認し、Cursor 扱いなら同じ％を出す。

## 「入っている」の判定

未インストールは出さない。判定は次のいずれか。

| プロバイダ | 入っている |
|---|---|
| Cursor | `/Applications/Cursor.app` がある、または `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` がある |
| Codex | `/Applications/ChatGPT.app` がある、または `~/.codex/auth.json` がある |
| Claude Code | `~/.claude.json`、`~/.claude/.credentials.json`、またはCLI実行ファイルがある |

アプリはあるが未ログインで数字が取れないときは、一覧には出す（「未ログイン」）。メニューバーはそのプロバイダが前面のときだけ警告表示。

## クリック後の一覧

前面に関係なく、入っているものだけ並べる。

各行の最低限:

- 名前（Cursor / Codex / Claude Code）
- いまの％（またはレガシーリクエスト枠）
- リセット時刻
- プラン名（取れるとき）

詳細ダッシュボード（モデル内訳・チャート）は cursor-usage の Webview を流用できる。初回は一覧＋％だけで出し、ダッシュボードは二段目でもよい。

## 更新タイミング

cursor-usage の `pollInterval`（既定 5 分）と同じくタイマーで取る。

拡張側の「文書編集」「ウィンドウフォーカス」トリガーはメニューバーでは使わない。前面アプリの切り替えは `NSWorkspace.didActivateApplicationNotification` で、**表示する数字の選択だけ**変える（取り直しはクールダウン中ならキャッシュ）。

## 言語

cursor-usage と同じ **日本語 / English / 简体中文**。`locale.ts` と `l10n/` をシステム言語向けに載せ替える。

## ホスト（確定）

メニューバーアプリとしての構造は **disk-monitor と同じ**。

- Swift / Cocoa、`LSUIElement`、`NSStatusItem`
- ルート `build.sh` → `mac/build.sh`
- Sparkle 直接配布（Developer ID・ノータライズ・ステープル）
- `MoveToApplicationsFolder` / About / フィードバック / ログイン時に開く
- 言語は `mac/Resources/{en,ja,zh-Hans}.lproj`

Electron にはしない。`windows/` は初回は作らない。詳細は [mac-host.md](mac-host.md)。

## 配布

Mac 直接配布（Developer ID + Sparkle）。App Store サンドボックスだと Cursor の `state.vscdb` と `~/.codex` が読めない。disk-monitor と同じ経路。

## やらないこと（初回）

- Claude Desktop / Web のプラン使用率取得
- VS Code 拡張化（既存 cursor-usage が担当）
- App Store
- 複数アカウント切り替え
- CodexBar 互換や全プロバイダ横断
