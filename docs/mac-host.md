# メニューバー本体 — disk-monitor と同じ構造

正本: `/Users/tomippe/Cursor/disk-monitor/`
コピー元のビルド: `disk-monitor/mac/build.sh` と `disk-monitor/build.sh`

AI Usage は **Mac のみ**。disk-monitor の `windows/` は持ち込まない。ip-monitor は Mac 単体の兄弟だが、構成の正本は disk-monitor の Mac 側。

## ディレクトリ（作るとき）

```
ai-usage/
  build.sh                 # exec ./mac/build.sh "$@"
  version.txt
  .env.example
  docs/
  mac/
    AIUsage.swift          # disk-monitor の ProcessMonitor.swift に相当
    build.sh
    icon.avif              # 角丸 icns 生成の元
    AppIcon.icns           # ビルドが生成してもよい
    Resources/
      en.lproj/            # InfoPlist.strings + Localizable.strings
      ja.lproj/
      zh-Hans.lproj/
    Sparkle.framework      # disk-monitor/mac から同梱
    Sparkle_bin/           # generate_appcast
    build/                 # gitignore。成果物 AI Usage.app
```

disk-monitor は実行ファイル名が `ProcessMonitor` でバンドル名が `Disk Monitor.app`。AI Usage は揃えてよい。

| 項目 | disk-monitor | AI Usage（案） |
|---|---|---|
| バンドル | `Disk Monitor.app` | `AI Usage.app` |
| 実行ファイル | `ProcessMonitor` | `AIUsage` |
| Bundle ID | `jp.tomippe.diskmonitor` | `jp.tomippe.ai-usage` |
| ソース | `mac/ProcessMonitor.swift` | `mac/AIUsage.swift` |
| 成果物 | `mac/build/` | `mac/build/` |
| 配布 | `../apps.tomippe.jp/disk-monitor/` | `../apps.tomippe.jp/ai-usage/` |
| `MAC_DIST_SLUG` | `disk-monitor` | `ai-usage` |
| `MAC_DIST_PKG` | `dmg` | `dmg`（同じ） |
| `MACOSX_DEPLOYMENT_TARGET` | `11.0` | `11.0` |
| `LSUIElement` | `true` | `true` |

## ビルドが必ず同梱する Swift（build-common）

`mac/build.sh` の `SWIFT_SOURCES` は disk-monitor と同じ並び。

| ファイル | 役割 |
|---|---|
| `mac/AIUsage.swift` | アプリ本体 |
| `../build-common/MoveToApplicationsFolder.swift` | `/Applications` へ移動（`~/Applications` 禁止、`ditto --norsrc`） |
| `../build-common/TomippeAppAbout.swift` | このアプリについて |
| `../build-common/TomippeRelaunch.swift` | 移動後の再起動 |
| `../build-common/TomippeFeedbackForm.swift` | メニュー「フィードバックを送る…」→ Airtable |

`SWIFT_FLAGS` も同じ: Cocoa + CoreServices + ServiceManagement + Sparkle、`@executable_path/../Frameworks`。

arm64 / x86_64 を別コンパイルして `lipo` で Universal。`-app` はアドホック署名で終了。フルビルドは `mac_sparkle_publish_direct_dist`。

## Info.plist（build.sh が生成）

disk-monitor のキーをそのまま使う。差し替えるのは名前・ID・URL だけ。

必須:

- `LSUIElement` = true（Dock に出さない）
- `CFBundleLocalizations` = en / ja / zh-Hans
- `ITSAppUsesNonExemptEncryption` = false
- `SUFeedURL` = `https://apps.tomippe.jp/ai-usage/appcast.xml`
- `SUPublicEDKey` = disk-monitor / 他 Sparkle アプリと同じ鍵
- `NSHumanReadableCopyright`

disk-monitor 固有の `NSAppleEventsUsageDescription`（ゴミ箱）は **付けない**。AI Usage は Finder を使わない。

ネットワークは HTTPS のみなので `NSAppTransportSecurity` の arbitrary loads は不要。

## 起動〜メニュー（ProcessMonitor.swift から踏襲する骨格）

`AppDelegate` の流れをそのまま使う。中身だけ使用量に差し替える。

1. `applicationWillFinishLaunching` → `MoveToApplicationsFolder.moveIfNecessary()`
2. `applicationDidFinishLaunching`
   - `NSStatusBar.system.statusItem(withLength: .variableLength)`
   - テンプレート画像 + `button.title`（disk-monitor は空き容量、こちらは `Cursor 32%` / `Codex 18%`）
   - `statusItem.menu = menu`
   - `SPUStandardUpdaterController(startingUpdater: true, …)`
   - `SMAppService.mainApp` で「ログイン時に開く」
   - タイマー開始
3. メニュー構築
   - 上段: 入っているプロバイダの一覧（％・リセット・プラン）
   - 区切り
   - 更新
   - ログイン時に開く
   - アップデートを確認（Sparkle）
   - フィードバックを送る…（`TomippeFeedbackForm.open(appName: "AI Usage")`）
   - このアプリについて
   - 終了
4. 前面アプリ
   - `NSWorkspace.didActivateApplicationNotification`
   - Cursor / Codex なら「直近アクティブ」を更新してタイトルを差し替え
   - それ以外はタイトルを変えない（直近を維持）

クリックは disk-monitor と同じく **メニュー**。WKWebView のポップオーバーは必須ではない。詳細ダッシュボードを後から足すなら、メニュー項目「ダッシュボード…」で別ウィンドウでもよい。

## ログイン時に開く / Sparkle / フィードバック

| 機能 | disk-monitor のやり方 | AI Usage |
|---|---|---|
| ログイン時に開く | `SMAppService.mainApp` | 同じ |
| 更新 | `SPUStandardUpdaterController` + メニュー | 同じ |
| フィードバック | `TomippeFeedbackForm.open(appName:)` | `appName: "AI Usage"`。Airtable の App 選択肢はビルド時に `airtable-add-feedback-apps.py "AI Usage by tomippe"` |
| 紹介ページ | メニューから URL | `https://apps.tomippe.jp/ai-usage/`（ページ作成後） |

## 配布ゲート（省略禁止）

`build-system.mdc` の Sparkle 直接配布と同じ。

- ZIP は `mac_create_dist_zip` のみ
- `verify-mac-distribution-post.sh` が exit 0 になるまで FTP しない
- 移動先は `/Applications` のみ

## やらないこと（構造）

- Electron / Bun ランタイムを .app に同梱しない（disk-monitor 型を崩す）
- MAS サンドボックス
- 初回の `windows/`
- cursor-usage の `vscode` ホストを残す

cursor-usage の TypeScript は **仕様と移植元**。動くアプリは Swift 一本。テスト用に `core/` へ TS を残すのは任意（実行時には使わない）。
