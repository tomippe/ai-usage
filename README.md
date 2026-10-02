# AI Usage

メニューバーに、前面アプリに応じた AI プラン使用量を出す Mac アプリ。

- **表示名**: AI Usage
- **スラッグ**: `ai-usage`
- **パス**: `/Users/tomippe/Cursor/ai-usage`
- **プロバイダ**: Cursor、Codex（ChatGPT.app / `~/.codex`）、Claude Code（statusline）

VS Code / Cursor 拡張の [cursor-usage](../cursor-usage) は別製品として残す。データ層・集計・ダッシュボードの仕様はそこから引き継ぐ。

**メニューバー本体の構造は [disk-monitor](../disk-monitor) と同じ。** Swift / Cocoa、`LSUIElement`、Sparkle 直接配布。Electron にはしない。Windows は初回対象外（`windows/` は作らない）。

## いまあるもの

| 種別 | 内容 |
|---|---|
| ビルド | `./build.sh` → `mac/build.sh`（Sparkle 直接配布・disk-monitor 型） |
| ルール | `.cursor/rules/build.mdc` |
| ソース | `mac/AIUsage.swift`（メニューバー骨格のみ。使用量は未実装） |
| 計画 | [docs/next-plan.md](docs/next-plan.md) |

| 文書 | 内容 |
|---|---|
| [docs/product.md](docs/product.md) | 製品仕様・決定事項 |
| [docs/handoff-from-cursor-usage.md](docs/handoff-from-cursor-usage.md) | cursor-usage からそのまま使えるコード |
| [docs/providers.md](docs/providers.md) | Cursor / Codex / Claude の取得経路 |
| [docs/mac-host.md](docs/mac-host.md) | メニューバー本体（disk-monitor 型）と配布 |
| [docs/app-page.md](docs/app-page.md) | 紹介ページ（公開済み） |

## まだやっていないこと

- `git remote` 設定（候補: `https://github.com/tomippe/ai-usage.git`）
- Cursor・Codex 使用量の Swift 実装・アイコン
- フル `./build.sh`（公証・FTP・配布）
