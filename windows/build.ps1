#Requires -Version 5.1
<#
.SYNOPSIS
    AI Usage Windows — EXE + MSIX (Microsoft Store)
.EXAMPLE
    .\build.ps1 -Exe      # portable EXE only（既定: 実行中の AIUsage を終了し、ビルド後に x64 EXE を起動）
    .\build.ps1           # EXE + signed MSIX bundle
    .\build.ps1 -NoStop -NoLaunch  # CI 等: 終了・起動をしない
#>
param(
    [switch]$Exe,
    [switch]$Clean,
    [switch]$Noverup,
    [switch]$NoStop,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Stop-RunningAiUsage {
    param([switch]$Skip)
    if ($Skip) { return }
    Get-Process -Name 'AIUsage' -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Stopping AIUsage (PID $($_.Id))..." -ForegroundColor Gray
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

function Wait-AiUsageFullyStopped {
    param([switch]$Skip, [int]$TimeoutSec = 20)
    if ($Skip) { return }
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSec)
    while ([datetime]::UtcNow -lt $deadline) {
        $left = @(Get-Process -Name 'AIUsage' -ErrorAction SilentlyContinue)
        if ($left.Count -eq 0) {
            Write-Host "AIUsage process ended." -ForegroundColor Gray
            return
        }
        Start-Sleep -Milliseconds 300
    }
    foreach ($p in @(Get-Process -Name 'AIUsage' -ErrorAction SilentlyContinue)) {
        Write-Host "AIUsage still alive; force kill PID $($p.Id)..." -ForegroundColor Yellow
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 400
}

function Get-DotNetExe {
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    foreach ($candidate in @(
            (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe')
            if ($pf86) { Join-Path $pf86 'dotnet\dotnet.exe' }
        )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    return $null
}

function Start-BuiltAiUsagePortable {
    param(
        [Parameter(Mandatory = $true)][string] $ExePath,
        [switch]$Skip
    )
    if ($Skip) { return }
    if (-not (Test-Path -LiteralPath $ExePath)) {
        Write-Warning "Built EXE not found: $ExePath"
        return
    }
    $dir = Split-Path -Parent $ExePath
    Write-Host "Starting: $ExePath" -ForegroundColor Cyan
    Start-Process -FilePath $ExePath -WorkingDirectory $dir
}

if ($env:TOMIPPE_BUILD_COMMON_ROOT -and (Test-Path -LiteralPath (Join-Path $env:TOMIPPE_BUILD_COMMON_ROOT 'windows-build-bootstrap.ps1'))) {
    . (Join-Path $env:TOMIPPE_BUILD_COMMON_ROOT 'windows-build-bootstrap.ps1')
} else {
    . (Join-Path $PSScriptRoot '..\..\build-common\windows-build-bootstrap.ps1')
}
$buildCommonRoot = Resolve-BuildCommonRoot -WindowsScriptRoot $PSScriptRoot
. (Join-Path $buildCommonRoot 'windows-unc-build.ps1')

# ステージドビルドが早期 exit するので、UNC 分岐より先に必ず「終了→待機」（= 常に [1] 終了 → [2] ビルド → [3] 起動）
if (-not $NoStop) {
    Write-Host "[1/3] Stop running AIUsage..." -ForegroundColor Cyan
    Stop-RunningAiUsage
    Wait-AiUsageFullyStopped
}

if ($env:TOMIPPE_WIN_BUILD_STAGED -ne '1') {
    $projRootForStage = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    if (Invoke-WindowsBuildViaLocalStageIfNeeded `
            -ProjectRoot $projRootForStage `
            -StageName 'ai-usage-win-build' `
            -ArtifactRelativePaths @('windows\build', 'windows\version.txt') `
            -BuildScriptRelative 'windows\build.ps1' `
            -BoundParameters $PSBoundParameters) {
        exit 0
    }
}

$rootDir = $PSScriptRoot
$projectRoot = Resolve-TomippeProjectRoot -WindowsScriptRoot $rootDir
$csproj = Join-Path $rootDir "AIUsage.Windows.csproj"
$assetsDir = Join-Path $rootDir "Assets"
$buildDir = Join-Path $rootDir "build"
$versionFile = Join-Path $rootDir "version.txt"
$rids = @("win-x64", "win-arm64")

function Find-MakeAppx {
    $sdkRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (-not (Test-Path $sdkRoot)) { return $null }
    Get-ChildItem $sdkRoot -Recurse -Filter "makeappx.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -like "*\x64" } |
        Sort-Object { $_.DirectoryName } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

. (Join-Path $rootDir "scripts\_msstore-env.ps1")
. (Join-Path $buildCommonRoot "helpers.ps1")
. (Join-Path $buildCommonRoot "version.ps1")

Write-Host "AI Usage Windows Build" -ForegroundColor White
$dotnetExe = Get-DotNetExe
if (-not $dotnetExe) {
    Write-Error ".NET SDK not found (dotnet not in PATH and not under Program Files)."
    exit 1
}
Write-Host "Using: $dotnetExe" -ForegroundColor Gray

Write-Host "[2/3] Build..." -ForegroundColor Cyan
$version = Read-AppVersion -VersionFile $versionFile
Write-Ok "v$version"

if ($Clean) {
    Remove-Item -Recurse -Force (Join-Path $rootDir "obj"), $buildDir -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

$storeLogo = Join-Path $assetsDir "StoreLogo.png"
$appIcon = Join-Path $assetsDir "app-icon.png"
# -Exe は portable のみ（MSIX 不要）。app-icon から Store 用 PNG を再生成（未生成 or ソース更新時）。
if (-not $Exe -and (Test-Path $appIcon)) {
    $regen = -not (Test-Path $storeLogo)
    if (-not $regen) {
        $regen = (Get-Item $appIcon).LastWriteTimeUtc -gt (Get-Item $storeLogo).LastWriteTimeUtc
    }
    if ($regen) {
        Write-Host "Generating Store assets..." -ForegroundColor Gray
        & (Join-Path $rootDir "generate-assets.ps1")
    }
}

foreach ($rid in $rids) {
    $arch = $rid -replace "win-", ""
    $outDir = Join-Path $buildDir "exe\$arch"
    & $dotnetExe publish $csproj -c Release -r $rid --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true `
        -p:DebugType=none -p:DebugSymbols=false `
        -o $outDir
    if ($LASTEXITCODE -ne 0) { Write-Error "Publish failed: $rid"; exit 1 }
    Write-Host "OK: $(Join-Path $outDir 'AIUsage.exe')" -ForegroundColor Green
}

if ($Exe) {
    if (-not $Noverup) { Save-NextAppVersion -Version $version -VersionFile $versionFile }
    $portableX64 = Join-Path $buildDir "exe\x64\AIUsage.exe"
    if (-not $NoLaunch) { Write-Host "[3/3] Relaunch AIUsage..." -ForegroundColor Cyan }
    Start-BuiltAiUsagePortable -ExePath $portableX64 -Skip:$NoLaunch
    exit 0
}

Load-MsStoreEnv -ProjectRoot $projectRoot
$signingPfx = Resolve-MsStoreSigningPfx -WindowsRoot $rootDir -ProjectRoot $projectRoot
if (-not $signingPfx) {
    Write-Error "MS_STORE_SIGNING_PFX not found (~/.msstore-env)."
    exit 1
}

$makeappx = Find-MakeAppx
if (-not $makeappx) { Write-Error "makeappx.exe not found (Windows SDK)."; exit 1 }

Remove-Item -Recurse -Force (Join-Path $buildDir "msix-content") -ErrorAction SilentlyContinue
# signtool は UNC パス上のパッケージで失敗することがある（0x800700a1）→ ローカル Temp へ出力して署名する
$projectRootFs = $projectRoot
if ($projectRootFs -match '^Microsoft\.PowerShell\.Core\\FileSystem::(.+)$') {
    $projectRootFs = $Matches[1]
}
$msixOutputDir = Join-Path $buildDir "msix"
if ($projectRootFs -like '\\*') {
    $msixOutputDir = Join-Path $env:TEMP "ai-usage-msix-$(Get-Random)"
}
New-Item -ItemType Directory -Path $msixOutputDir -Force | Out-Null

$msixVersion = "$version.0"
$msixFiles = @()
$manifestSrc = Join-Path $rootDir "Package.appxmanifest"

foreach ($rid in $rids) {
    $arch = $rid -replace "win-", ""
    $contentDir = Join-Path $buildDir "msix-content\$arch"
    & $dotnetExe publish $csproj -c Release -r $rid --self-contained true `
        -p:DebugType=none -p:DebugSymbols=false -o $contentDir
    if ($LASTEXITCODE -ne 0) { Write-Error "MSIX publish failed: $rid"; exit 1 }

    $contentAssets = Join-Path $contentDir "Assets"
    New-Item -ItemType Directory -Path $contentAssets -Force | Out-Null
    Copy-Item (Join-Path $assetsDir "*.png") $contentAssets -Force

    $manifestContent = Get-Content $manifestSrc -Raw -Encoding UTF8
    $manifestContent = $manifestContent -replace '(<Identity[^>]*?)Version="[^"]*"', "`$1Version=`"$msixVersion`""
    if ($manifestContent -match 'ProcessorArchitecture=') {
        $manifestContent = $manifestContent -replace '(<Identity[^>]*?)ProcessorArchitecture="[^"]*"', "`$1ProcessorArchitecture=`"$arch`""
    } else {
        $manifestContent = $manifestContent -replace '(<Identity[^>]*?)(/>|\s*>)', "`$1`n            ProcessorArchitecture=`"$arch`"`$2"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $contentDir "AppxManifest.xml"), $manifestContent, $utf8NoBom)

    $msixPath = Join-Path $msixOutputDir "AIUsage_$arch.msix"
    & $makeappx pack /d $contentDir /p $msixPath /o
    if ($LASTEXITCODE -ne 0) { Write-Error "makeappx pack failed"; exit 1 }
    Sign-StorePackage -PackagePath $msixPath -PfxPath $signingPfx
    $msixFiles += $msixPath
    Write-Host "OK: $msixPath" -ForegroundColor Green
}

$bundleDir = Join-Path $buildDir "msix-bundle-content"
Remove-Item -Recurse -Force $bundleDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
foreach ($msix in $msixFiles) { Copy-Item $msix $bundleDir }
$bundlePath = Join-Path $msixOutputDir "AIUsage.msixbundle"
& $makeappx bundle /d $bundleDir /p $bundlePath /bv $msixVersion /o
Sign-StorePackage -PackagePath $bundlePath -PfxPath $signingPfx
Write-Host "OK: $bundlePath" -ForegroundColor Green

Remove-Item -Recurse -Force $bundleDir, (Join-Path $buildDir "msix-content") -ErrorAction SilentlyContinue

if ($projectRootFs -like '\\*') {
    $bundleDestDir = Join-Path $buildDir "msix"
    New-Item -ItemType Directory -Path $bundleDestDir -Force | Out-Null
    $bundleDest = Join-Path $bundleDestDir "AIUsage.msixbundle"
    Copy-Item -LiteralPath $bundlePath -Destination $bundleDest -Force
    if ($msixOutputDir.StartsWith($env:TEMP, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -Recurse -Force $msixOutputDir -ErrorAction SilentlyContinue
    }
    $bundlePath = $bundleDest
}

if (-not $Noverup) { Save-NextAppVersion -Version $version -VersionFile $versionFile }

Write-Host "Store bundle: $bundlePath" -ForegroundColor Cyan

$portableX64 = Join-Path $buildDir "exe\x64\AIUsage.exe"
if (-not $NoLaunch) { Write-Host "[3/3] Relaunch AIUsage..." -ForegroundColor Cyan }
Start-BuiltAiUsagePortable -ExePath $portableX64 -Skip:$NoLaunch
