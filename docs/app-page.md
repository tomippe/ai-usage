# AI Usage 紹介ページ設定

## 公開ステータス

**公開済み**（`status: publish`）。

## URL

- 紹介ページ: https://apps.tomippe.jp/ai-usage/
- プライバシーポリシー: https://apps.tomippe.jp/ai-usage/policy/

## WordPress 投稿 ID

| 用途 | ID |
|------|-----|
| 紹介ページ（app） | **2534** |
| プライバシーポリシー（app・子ページ） | **2535** |

## キャッチフレーズ（app-cp）

前面の AI の使い方がひと目で分かる
Cursor と Codex の使用率をメニューバーに

（HTML は中央寄せ 2 行。WordPress ACF `app-cp` に設定済み。）

## デザイン

| 項目 | 値 |
|------|-----|
| **キー色（app-keycolor）** | `#333333`（濃いグレー） |
| **KV（app-kvbg）** | メディア ID **2536**。正本 **`mac/kv-background.jpg`**（ユーザー指定のテック／バーチャート系 KV。**Vecteezy 水印入り**の素材をそのまま使用） |
| **app-kvbgaddcss** | `background-color: rgba(0, 0, 0, 0.4);` ＋ **`exclusion`**。必須4行: |
| | `background-repeat: no-repeat;` |
| | `background-position: center;` |
| | `background-size: cover;` |
| | `background-blend-mode: exclusion;` |
| **アイコン意匠** | 正本 **`mac/icon.svg`** — 丸角四角、グラデ `#ff3399` → `#660066`、三本のバー（使用率メーター）。cursor-usage の緑は不使用。 |
| **app-icon** | メディア ID **2532**（SVG から 512px PNG をパイプアップロード） |
| **app-ss01** | メディア ID **2542**（正本 **`ss/app-ss01.png`** 2090×1310） |
| **app-ss01width** | **1600**（ACF 上限。画像本体は 2090px をアップロードして縮小表示） |

## プラットフォーム

- **platform**: `["mac"]`
- **app-macdesc**: `macOS 11+, DMG<br>日本語,English,中文`
- **app-macversion**: `1.0.1`
- **app-macpkg**: `dmg`
- **配布**: Sparkle 直接配布（DMG 公開済み: https://apps.tomippe.jp/ai-usage/）

## フィードバック

- Airtable prefill_App: `AI Usage`（紹介ページ `post_title` と一致。`airtable-add-feedback-apps.py "AI Usage"`）

## 拡張ページとの関係

https://apps.tomippe.jp/cursor-usage/ は VS Code / Cursor 拡張のまま。KV・アイコン・キー色は別デザイン。

## メディア再アップロード（アイコン）

```bash
source ~/.wp-env && source .env
magick -background none mac/icon.svg -resize 512x512 png:- | curl -s -u "$WP_USER:$WP_APP_PASSWORD" \
  -H "Content-Disposition: attachment; filename=ai-usage-icon.png" \
  -H "Content-Type: image/png" --data-binary @- \
  "$WP_SITE_URL/wp-json/wp/v2/media"
# 返却 ID を app-icon に PATCH
```

Mac `AppIcon.icns` は `./build.sh -app` 実行時に `mac/icon.svg` から自動生成（git 管理外）。

## メディア再アップロード（KV）

```bash
source ~/.wp-env && source .env
curl -s -u "$WP_USER:$WP_APP_PASSWORD" \
  -H "Content-Disposition: attachment; filename=ai-usage-kv-background.jpg" \
  -H "Content-Type: image/jpeg" \
  --data-binary @mac/kv-background.jpg \
  "$WP_SITE_URL/wp-json/wp/v2/media"
# 返却 ID を app-kvbg に PATCH（app-kvbgaddcss は上表のとおり）
```
