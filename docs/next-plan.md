# AI Usage — さらなる計画（2026-10-02）

ビルド下準備完了後のロードマップ。正本仕様は `docs/product.md`・`docs/handoff-from-cursor-usage.md`・`docs/providers.md`・`docs/mac-host.md`。

## フェーズ 0 — 完了（ビルド準備）

- [x] ルート `build.sh` → `mac/build.sh`（disk-monitor 型・Sparkle 直接配布）
- [x] `.cursor/rules/build.mdc`
- [x] `version.txt`（初回 `0.1.0`）
- [x] `.env.example` / `.gitignore`
- [x] `mac/AIUsage.swift` スキャフォールド（メニューバー骨格のみ）
- [x] Sparkle symlink（`disk-monitor/mac`）
- [x] ローカライズ `.lproj`（en / ja / zh-Hans）

## フェーズ 1 — リポジトリ・配布の土台

| # | 作業 | 備考 |
|---|------|------|
| 1.1 | ~~`git init` + `.gitignore` 確認 + 初回コミット~~ **済** | フル `./build.sh` は Git コミット段階で必要 |
| 1.2 | `mac/icon.avif` または `AppIcon.icns` | 紹介ページ用アイコンと揃える |
| 1.3 | Airtable フィードバック | `airtable-add-feedback-apps.py "AI Usage by tomippe"` |
| 1.4 | `./build.sh -app` で日常確認 | フルビルドは紹介ページ・初回配布前でも可 |

## フェーズ 2 — コア機能（Swift 移植）— **初版済（v0.1.0 ローカル）**

| 項目 | 状態 |
|---|---|
| Cursor 使用量 | `CursorUsageClient.swift`（`cursor-api.ts` 相当: SQLite / stripe+usage / GetCurrentPeriodUsage / チーム） |
| Codex 使用量 | `CodexUsageClient.swift`（ChatGPT.app 同梱 `codex app-server`、`account/rateLimits/read`） |
| 入っている判定 | `ProviderAvailability.swift` |
| 前面アプリ切替 | `AIUsage.swift`（Cursor / Codex / CursorWrap、直近 UserDefaults） |
| メニューバー | SVG 意匠 `MenuBarIcon`（`icon.svg` 由来）＋数値。SF Symbol ゲージは不使用 |
| メニュー一覧 | プロバイダ行・週間/5h（Codex）・リセット・プラン |
| ポーリング | 5 分、クールダウン中は再取得スキップ（前面切替は表示のみ） |

後回し: Claude、ダッシュボード（WKWebView）、モデル内訳、拡張の minimalMode / オンデマンド併記、Cursor WAL 手動走査（現状は SQLite3 読取）。

## フェーズ 3 — 紹介ページ・ポリシー

| # | 作業 | 判断 |
|---|------|------|
| 3.1 | ~~apps.tomippe.jp 紹介ページ作成~~ **済** | [公開](https://apps.tomippe.jp/ai-usage/)。KV・キー色 `#ff3399`・アイコン `mac/icon.svg` |
| 3.2 | ~~`.env` に `WP_APP_POST_ID` 等~~ **済**（ローカルのみ・非コミット） | 正本 ID は `docs/app-page.md` |
| 3.3 | ~~プライバシーポリシー子ページ~~ **済** | https://apps.tomippe.jp/ai-usage/policy/ |
| 3.4 | スクリーンショット | メニューバー実画面が取れる実装後 |

## フェーズ 4 — 初回直接配布

1. 紹介ページ URL が有効であること
2. `./build.sh -cm "初回配布"`（Developer ID・公証・FTP・manifest）
3. `verify-mac-distribution-post.sh` exit 0 を確認
4. Sparkle appcast / DMG が `apps.tomippe.jp/ai-usage/` に載ること

## 判断が必要な項目

- ~~**キャッチフレーズ / KV / キー色**~~ → 紹介ページ作成時に確定（`docs/app-page.md`）
- **git remote**（新規リポジトリの置き場: ローカルのみ / GitHub / Origin）
- ~~**初回リリース版番号**~~ → **0.1.0** で確定（2026-10-02）

## 参照プロジェクト

- 殻・ビルド: [disk-monitor](/Users/tomippe/Cursor/disk-monitor)
- Mac 単体・紹介ページ例: [ip-monitor](/Users/tomippe/Cursor/ip-monitor)
- データ仕様: [cursor-usage](/Users/tomippe/Cursor/cursor-usage)
