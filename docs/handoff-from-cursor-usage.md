# cursor-usage からの引き継ぎ

正本: `/Users/tomippe/Cursor/cursor-usage/`
拡張 ID: `tomippe.cursor-usage`（Open VSX に残す。このアプリとは別製品）

メニューバーの殻は disk-monitor（Swift）。ここは **データと表示ロジック** の引き継ぎ。実装は Swift に移植する。TypeScript を .app に載せない。

## 層

| 層 | cursor-usage | vscode 依存 | AI Usage での扱い |
|---|---|---|---|
| 認証・API | `src/cursor-api.ts` | なし | **ほぼそのまま移植**。型とエンドポイントを正本にする |
| 集計 | `src/dashboard-state.ts` `src/model-breakdown.ts` `src/duration-options.ts` | なし | メニュー詳細や後段ダッシュボード用。初回メニューだけなら後回し可 |
| 整形 | `src/format.ts` `src/tooltip.ts` `src/locale.ts` | locale / tooltip が一部 vscode | システム言語に差し替えて移植 |
| 文言 | `src/i18n.ts` + `l10n/*.json` + `package.nls.*` | vscode.l10n | `Localizable.strings` に移す。キーと英語原文は流用 |
| ダッシュボード UI | `media/dashboard/*` + `src/dashboard-panel.ts` | webview | 初回はメニュー一覧。後段で WKWebView にするなら JS/CSS を流用 |
| 拡張の殻 | `src/extension.ts` | 全部 | **捨てる**。disk-monitor の `AppDelegate` に置き換え |

## ファイル単位

### そのまま仕様正本（移植必須）

#### `src/cursor-api.ts`（最重要）

vscode を import していない。メニューバーの Cursor 数字はこれだけで足りる。

**認証**

- DB: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`（darwin）
- キー: `cursorAuth/accessToken`（JWT）、`cursorAuth/cachedEmail`
- 自前 SQLite リーダ（native binding なし）。`ItemTable` を btree 走査。**WAL も読む**（`state.vscdb-wal`）。Cursor 起動中は WAL にしか新しいトークンが無い
- JWT の `sub` から `userId`、`sessionToken = userId%3A%3Ajwt`
- キャッシュ TTL 10 秒

**セットアップ（初回だけ）**

- `GET https://cursor.com/api/auth/stripe` → プラン名、チーム、オンデマンド可否
- `GET https://cursor.com/api/usage?user={userId}` → レガシーリクエスト枠
- Cookie: `WorkosCursorSessionToken={sessionToken}`、Origin/Referer は `cursor.com`

**使用量**

- 個人: usage API + `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`（Bearer JWT、`Connect-Protocol-Version: 1`）
- チーム: `POST https://cursor.com/api/dashboard/get-team-spend`
- イベント: `POST https://cursor.com/api/dashboard/get-filtered-usage-events`（最大 10 ページ × 500）
- 日次（チーム）: `POST https://cursor.com/api/dashboard/get-daily-spend-by-category`

**型（Swift でも同じ形）**

```
UsagePayload
  planName: String?
  includedRequests: (used, limit)
  onDemand: disabled | limited | unlimited + spendDollars + limitDollars?
  resetsAt: Date?
  totalPercentUsed / autoPercentUsed / apiPercentUsed: Double?

UsageEvent
  timestamp, model, kind, totalTokens, requests, spendCents, maxMode

DailySpendRow
  day, category, spendCents, totalTokens
```

プラン名正規化 `formatPlanName`: ultra→Ultra、pro_plus→Pro+ など。関数ごと移植。

メニューバーに出す Cursor の％:

- `totalPercentUsed != nil` → その数字（Ultra / 現行spendプラン）
- それ以外 → `used/limit` のレガシー枠
- オンデマンドは詳細メニュー。ミニマル表示は拡張の `minimalMode` と同じ考えで後から設定にできる

タイムアウト 15 秒。失敗時は前回値を残す（拡張と同じ）。

#### `src/format.ts`

`formatTokens`: 1000→K、1e6→M、1e9→B。イベント表を出すなら移植。

#### `src/dashboard-state.ts`

`buildDashboardState` / `filterEventsForRange` / `aggregateChartSeries` / `summarizeRange`。vscode なし。ダッシュボードを後段で出すときの正本。

#### `src/model-breakdown.ts`

期間 `1d | 7d | 30d | billingCycle`、モデル集計、ソート。`getDurationCutoff` が課金サイクル開始を `resetsAt` の1ヶ月前にしている。

#### `src/duration-options.ts`

期間ラベルと「billingCycle が無いときは 30d」。i18n だけ差し替え。

### 少し直して移植

#### `src/locale.ts`

`vscode.env.language` → `Bundle.main.preferredLocalizations` / `Locale.current`。

残す関数: `formatShortDate`、`formatChartDayLabel`、`formatDateTime`、`formatTime`。CJK は `yyyy年M月d日`。チャート日は UTC。

#### `src/i18n.ts`

英語原文がキー。`l10n/bundle.l10n.ja.json` と `bundle.l10n.zh-cn.json` を `Localizable.strings` に移す。

名前の差し替え:

- "Cursor Usage" → アプリ名は "AI Usage"
- プロバイダ行の見出しは "Cursor" / "Codex" のまま

`formatResetDate`（「N 日後の日付にリセット」）はメニューに出す。移植する。

`package.nls.json` / `.ja` / `.zh-cn` は拡張設定用。設定をメニューに足すときの文言元。

#### `src/tooltip.ts`

ステータスバー用 Markdown。メニューバーでは Markdown 不要。**数字の組み立てだけ**使う。

- `formatPlanPercent`（0.05 未満の誤差は整数％）
- Total / First-party / API / On-demand の並び
- オンデマンド `disabled` は隠す

### 初回は捨てる（後で必要なら戻す）

| ファイル | 理由 |
|---|---|
| `src/extension.ts` | StatusBarItem、コマンド、文書変更デバウンス、テーマ。disk-monitor の AppDelegate が代替 |
| `src/dashboard-panel.ts` | vscode Webview。CSP・nonce は WKWebView にするとき参考 |
| `media/dashboard/dashboard.js` `.css` `chart.umd.js` | 後段ダッシュボード用にコピー可。CSV の `=+@-` インジェクション対策は残す |
| `test/package-config.spec.ts` | 拡張 package.json 専用 |
| `test/config-duration.spec.ts` | 拡張設定スキーマ |
| Open VSX / vsce / `scripts/publish-ovsx.sh` | Mac アプリでは使わない |

### テスト（移植の回帰）

Bun テスト。Swift 化したら同じケースを XCTest にするか、一時的に `core/` で Bun のまま残す。

| テスト | 見るもの |
|---|---|
| `test/cursor-db-reader.spec.ts` | ItemTable と WAL から accessToken / email |
| `test/dashboard-state.spec.ts` | チャート・期間・フィルタ |
| `test/model-breakdown.spec.ts` | モデル集計とソート |
| `test/duration-options.spec.ts` | billingCycle フォールバック |
| `test/tooltip.spec.ts` | ％表示と概要行 |
| `test/dashboard-security.spec.ts` | CSV 式インジェクション |

## 拡張の設定 → メニューバー設定

| cursorUsage.* | 既定 | 初回 |
|---|---|---|
| `pollInterval` | 5 分（1/5/10/30/60） | タイマー。同じ既定 |
| `minimalMode` | false | 後回し。メニューバーは「プラン \| ％」程度 |
| `usageDuration` | billingCycle | 詳細を出すとき |
| `modelBreakdownSortBy` / `SortOrder` | tokens / desc | ダッシュボード後段 |
| `excludeZeroTokenModels` | false | 後段 |
| `quotaAwareEventDisplay` | true | 後段。Included の spend を 0 扱い |

永続化は `UserDefaults`（disk-monitor と同じ）。vscode settings.json は読まない。

## 更新トリガーの読み替え

| 拡張 | メニューバー |
|---|---|
| 起動時 `updateUsage()` | `applicationDidFinishLaunching` で初回取得 |
| `pollInterval` 分ごと | `Timer`（disk-monitor の `refreshInterval` と同じ置き方） |
| 文書変更デバウンス 30 秒 | **やらない** |
| ウィンドウフォーカス | **やらない**（前面切り替えは表示対象の選択だけ） |
| 設定変更でステータス再描画 | UserDefaults 変更でタイトル再描画 |
| テーマ変更でバー色 | メニューバーはテンプレート画像。不要 |

## 表示ロジック（拡張の `updateStatusBar`）

移植する判定:

```
premiumExhausted = totalPercentUsed >= 100
                または (レガシーかつ used >= limit)
出す文字 = planName があれば "Plan | " + ％（または used/limit）
オンデマンドは詳細メニュー。メニューバー本文は％を優先
取れない = 警告タイトル。前回値があれば前回のまま
```

拡張の `$(pulse)` アイコンは SF Symbol に置き換え（disk-monitor が `internaldrive` をテンプレート表示しているのと同じ）。

## 言語ファイルの置き場

```
cursor-usage/l10n/bundle.l10n.json          → 英語原文（キー）
cursor-usage/l10n/bundle.l10n.ja.json       → mac/Resources/ja.lproj/Localizable.strings
cursor-usage/l10n/bundle.l10n.zh-cn.json    → mac/Resources/zh-Hans.lproj/Localizable.strings
cursor-usage/src/i18n.ts Msg                → キー一覧
```

disk-monitor は `NSLocalizedString`。同じにする。

## ビルド・紹介ページから引き継がないもの

cursor-usage の `build.sh` は VSIX / Open VSX 用。**使わない**。ビルドは disk-monitor 型（[mac-host.md](mac-host.md)）。

紹介ページの KV・スクショ・キー色 `#97cc64` は拡張用。AI Usage は別アイコン・別ページ。フィードバックの App 名は `AI Usage`（拡張の `Cursor Usage by tomippe` は残す）。
