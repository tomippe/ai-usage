#Requires -Version 5.1
# Generates Microsoft Store PNG assets from Assets\app-icon.png（背景は紫グラデ、白い棒）

param(
    [switch]$Force
)

$rootDir = $PSScriptRoot
$repoRoot = Split-Path $rootDir -Parent
$sourceImg = Join-Path $rootDir "Assets\app-icon.png"
$assetsDir = Join-Path $rootDir "Assets"

function Find-MagickExe {
    if ($env:MAGICK_HOME) {
        $candidate = Join-Path $env:MAGICK_HOME "magick.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $cmd = Get-Command magick -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function New-StoreAppIcon {
    param(
        [Parameter(Mandatory = $true)][string]$OutPng,
        [Parameter(Mandatory = $true)][string]$Magick
    )
    $size = 512
    $args = @(
        "-size", "${size}x${size}", "gradient:#ff3399-#660066",
        "-fill", "white", "-draw",
        "roundrectangle 113.78,170.76 156.44,398.24 21.33,21.33 roundrectangle 234.67,256 277.33,398.24 21.33,21.33 roundrectangle 355.55,113.78 398.21,398.24 21.33,21.33",
        $OutPng
    )
    & $Magick @args
    if ($LASTEXITCODE -ne 0) {
        Write-Error "magick failed (exit $LASTEXITCODE)"
        exit 1
    }
    return $true
}

$magick = Find-MagickExe
if ($magick) {
    $regenMaster = $Force -or -not (Test-Path -LiteralPath $sourceImg)
    if (-not $regenMaster) {
        $regenMaster = (Get-Item -LiteralPath $PSCommandPath).LastWriteTimeUtc -gt (Get-Item -LiteralPath $sourceImg).LastWriteTimeUtc
    }
    if ($regenMaster) {
        Write-Host "Rendering square app-icon.png from purple gradient and white usage bars..." -ForegroundColor Cyan
        New-StoreAppIcon -OutPng $sourceImg -Magick $magick | Out-Null
    }
} elseif (-not (Test-Path -LiteralPath $sourceImg)) {
    Write-Error "Place a 512px PNG at $sourceImg or install ImageMagick (see Assets\README.md)."
    exit 1
}

if (-not (Test-Path -LiteralPath $sourceImg)) {
    Write-Error "app-icon.png missing after render."
    exit 1
}

if (-not (Test-Path $assetsDir)) {
    New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
}

Write-Host "Source: $sourceImg"

function Save-Png {
    param([string]$Path, [int]$Width, [int]$Height)
    if ($magick) {
        & $magick $sourceImg -filter Lanczos -resize "${Width}x${Height}!" $Path
        if ($LASTEXITCODE -ne 0) {
            Write-Error "magick resize failed (exit $LASTEXITCODE): $Path"
            exit 1
        }
    } else {
        Add-Type -AssemblyName System.Drawing
        $original = [System.Drawing.Image]::FromFile($sourceImg)
        $bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.DrawImage($original, 0, 0, $Width, $Height)
        $g.Dispose()
        $original.Dispose()
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
    Write-Host "  $Path ($Width x $Height)"
}

Save-Png (Join-Path $assetsDir "StoreLogo.png") 50 50
Save-Png (Join-Path $assetsDir "Square44x44Logo.png") 44 44
Save-Png (Join-Path $assetsDir "Square71x71Logo.png") 71 71
Save-Png (Join-Path $assetsDir "Square150x150Logo.png") 150 150
Save-Png (Join-Path $assetsDir "Square310x310Logo.png") 310 310
Save-Png (Join-Path $assetsDir "SplashScreen.png") 620 300
Save-Png (Join-Path $assetsDir "Wide310x150Logo.png") 310 150

Write-Host "Done."
