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

## フェーズ 2 — コア機能（Swift 移植）

優先順（handoff 正本どおり）:

1. **Cursor 使用量** — `cursor-usage/src/cursor-api.ts` を Swift 化（SQLite + WAL、`state.vscdb`、JWT、usage API）
2. **Codex 使用量** — `docs/providers.md` の `~/.codex` / ChatGPT.app 経路
3. **「入っている」判定** — `product.md` の表（アプリ存在 or 認証ファイル）
4. **前面アプリ切替** — `NSWorkspace.didActivateApplicationNotification`、bundle id 表 + CursorWrap 確認
5. **メニューバー表示** — 前面／直近アクティブの％、未ログイン時の警告
6. **メニュー一覧** — 入っているプロバイダのみ、％・リセット・プラン名
7. **ポーリング** — 既定 5 分、失敗時はキャッシュ維持

後回し: Claude、ダッシュボード（WKWebView）、モデル内訳。

## フェーズ 3 — 紹介ページ・ポリシー

| # | 作業 | 判断 |
|---|------|------|
| 3.1 | apps.tomippe.jp 紹介ページ作成 | `docs/app-page.md`。KV・キー色・アイコンは **ユーザー確認** |
| 3.2 | `.env` に `WP_APP_POST_ID` 等 | 作成後 |
| 3.3 | プライバシーポリシー子ページ | disk-monitor に倣うか要確認（個人データ非収集の声明） |
| 3.4 | スクリーンショット | メニューバー実画面が取れる実装後 |

## フェーズ 4 — 初回直接配布

1. 紹介ページ URL が有効であること
2. `./build.sh -cm "初回配布"`（Developer ID・公証・FTP・manifest）
3. `verify-mac-distribution-post.sh` exit 0 を確認
4. Sparkle appcast / DMG が `apps.tomippe.jp/ai-usage/` に載ること

## 判断が必要な項目

- **キャッチフレーズ**（`docs/app-page.md` 案は未確定）
- **KV 背景・キー色**（cursor-usage の `#97cc64` は流用しない）
- **git remote**（新規リポジトリの置き場: ローカルのみ / GitHub / Origin）
- ~~**初回リリース版番号**~~ → **0.1.0** で確定（2026-10-02）

## 参照プロジェクト

- 殻・ビルド: [disk-monitor](/Users/tomippe/Cursor/disk-monitor)
- Mac 単体・紹介ページ例: [ip-monitor](/Users/tomippe/Cursor/ip-monitor)
- データ仕様: [cursor-usage](/Users/tomippe/Cursor/cursor-usage)
