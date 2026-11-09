# AI Usage — Microsoft Store

## 前提

- Windows 10 SDK（`makeappx.exe`）
- .NET 10 SDK
- Partner Center のアプリ登録（Store ID 取得後 `.env` に設定）
- 署名 PFX: `%USERPROFILE%\.msstore-env`（`build-common/msstore-env.example`）

## ビルド

```powershell
cd windows
.\generate-assets.ps1   # Assets\app-icon.png が必要
.\build.ps1 -Exe        # ポータブル EXE のみ
.\build.ps1             # EXE + 署名済み MSIX / msixbundle
```

成果物: `windows/build/msix/AIUsage.msixbundle`（Partner Center 提出用）

## 掲載文言

正本: [docs/store-metadata.md](../docs/store-metadata.md)

## 提出

```bash
# Mac / WSL（msstore CLI 設定済み）
source ~/.msstore-env && source .env
./scripts/msstore-publish.sh
```

手順詳細: `build-common/microsoft-store-setup.md`

## Partner Center 初回

1. Partner Center の **Package/Identity/Name**（例: `StudioTomippe.AIUsageChatGPTClaudeCursorMonitor`）と `Package.appxmanifest` の `<Identity Name="...">` を一致させる（Publisher CN も同様）
2. `MS_STORE_PRODUCT_ID` を `.env` に記録
3. プライバシー URL: https://apps.tomippe.jp/ai-usage/policy/
4. 年齢区分・データ収集なし（Mac 版と同趣旨）
