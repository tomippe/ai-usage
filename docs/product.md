# AI Usage 製品仕様

2026-10-02、cursor-usage リポジトリでの会話で決めた内容。

## 名前

| 項目 | 値 |
|---|---|
| 表示名 | **AI Usage** |
| スラッグ | `ai-usage` |
| バンドル ID（案） | `jp.tomippe.ai-usage` |
| 紹介ページ投稿タイトル | `AI Usage` |
| 拡張「Cursor Usage」 | 別製品。Open VSX はそのまま |

「LLM Usage」は正確だが、メニューバーと紹介ページでは AI の方が自然、でこれに決めた。既存の Disk Monitor / IP Monitor と同じ短い普通の言葉。

## 何をするか

1. **いま前面の対応アプリ**の使用率（％）を出す。Mac はメニューバー、Windows はフローティング小窓に表示する。
2. Mac はクリック、Windows は右クリックで、**入っているプロバイダだけ**一覧
3. 入っていないプロバイダはメイン表示にも一覧にも出さない

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

数字が取れないとき（未ログイン・取得失敗・未取得）は、一覧にも出さない。メニューバーは、表示対象のプロバイダのうち前面／直近アクティブのものを出す。

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

## Mac ホスト（確定）

メニューバーアプリとしての構造は **disk-monitor と同じ**。

- Swift / Cocoa、`LSUIElement`、`NSStatusItem`
- ルート `build.sh` → `mac/build.sh`
- Sparkle 直接配布（Developer ID・ノータライズ・ステープル）
- `MoveToApplicationsFolder` / About / フィードバック / ログイン時に開く
- 言語は `mac/Resources/{en,ja,zh-Hans}.lproj`

Electron にはしない。詳細は [mac-host.md](mac-host.md)。Windows 版の実装方針は [windows/README.md](../windows/README.md)。

## Windows ホスト

- .NET 10 / WPF の小さな最前面ウィンドウを使う。
- 窓のどこをドラッグしても移動でき、右クリックでMac版と同じ項目を持つコンテキストメニューを開く。
- Cursor / Codex / Claude Code の取得元と、音声しきい値、通貨、ログイン時起動を用意する。
- Windows版の更新確認は GitHub Releases を開く。Sparkle はMac版だけで使う。

## 配布

Mac 直接配布（Developer ID + Sparkle）。App Store サンドボックスだと Cursor の `state.vscdb` と `~/.codex` が読めない。disk-monitor と同じ経路。

## 音声通知

- 「音声通知」メニューで機能全体を有効化し、残り 50 / 40 / 30 / 20 / 10 / 5 / 0% の各しきい値を個別に選べる。初期状態は無効、しきい値はすべて選択済み。
- しきい値項目にマウスを乗せるとプレビューを読む。別項目へ移動すると前のプレビューを止めて、新しい値を読む。クリック時はチェック状態だけを切り替える。
- Cursor / ChatGPT / Claude Code の取得済み使用量を監視する。短期・週間など複数枠がある場合は、最も少ない残量をそのプロバイダの代表値にする。
- 読み上げ文とプロバイダ名の読み方はアプリの言語（日本語 / English / 简体中文）に合わせる。日本語では「ChatGPT」を「チャットGPT」、「Cursor」を「カーソル」と読む。
- 起動後の最初の取得値は基準として使い、読み上げない。以降、残量がしきい値に達したときに通知する。ポーリング間に複数段階を通過した場合は、最も低い通過段階だけを読む。回復してしきい値より 5 ポイント上になれば、その段階は再通知可能になる。
- しきい値の判定はプラットフォームごとに同じ状態遷移を使い、音声合成とメニュー設定は各 OS の実装に分離する。

## やらないこと（初回）

- Claude Desktop / Web のプラン使用率取得
- VS Code 拡張化（既存 cursor-usage が担当）
- App Store
- 複数アカウント切り替え
- CodexBar 互換や全プロバイダ横断
