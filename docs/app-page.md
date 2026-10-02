# AI Usage 紹介ページ設定

未作成。下準備と初回ビルドのときに作る。

## 予定

| 項目 | 値 |
|---|---|
| スラッグ | `ai-usage` |
| 投稿タイトル | `AI Usage by tomippe` |
| URL | `https://apps.tomippe.jp/ai-usage/` |
| platform | `["mac"]` |
| app-macdesc | `macOS 11+, DMG<br>日本語,English,中文` |
| 配布 | Sparkle DMG（disk-monitor と同じ） |
| フィードバック prefill_App | `AI Usage by tomippe` |

キャッチフレーズ案（未確定）:

前面の AI の使用量をメニューバーに
Cursor と Codex の消化率を切り替えて表示

## 拡張ページとの関係

`https://apps.tomippe.jp/cursor-usage/` は VS Code / Cursor 拡張のまま残す。KV・アイコン・キー色 `#97cc64` は流用しない。AI Usage 用に別アイコンを用意する。

## まだ無いもの

- `WP_APP_POST_ID` / `.env`
- アイコン・スクリーンショット・KV・キー色
- プライバシーポリシー（直接配布 Mac でも用意するなら disk-monitor に倣う）
