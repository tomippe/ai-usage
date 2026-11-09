#Requires -Version 5.1
# Generates Microsoft Store PNG assets from Assets\app-icon.png

Add-Type -AssemblyName System.Drawing

$rootDir = $PSScriptRoot
$sourceImg = Join-Path $rootDir "Assets\app-icon.png"
$assetsDir = Join-Path $rootDir "Assets"

if (-not (Test-Path $sourceImg)) {
    Write-Error "Place a 512px PNG at $sourceImg (see Assets\README.md)."
    exit 1
}

if (-not (Test-Path $assetsDir)) {
    New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
}

$original = [System.Drawing.Image]::FromFile($sourceImg)
Write-Host "Source: $sourceImg ($($original.Width)x$($original.Height))"

function Resize-Image {
    param([System.Drawing.Image]$Source, [int]$Width, [int]$Height)
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($Source, 0, 0, $Width, $Height)
    $g.Dispose()
    return $bmp
}

function Save-Png {
    param([System.Drawing.Image]$Source, [string]$Path, [int]$Width, [int]$Height)
    $bmp = Resize-Image -Source $Source -Width $Width -Height $Height
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "  $Path ($Width x $Height)"
}

Save-Png $original (Join-Path $assetsDir "StoreLogo.png") 50 50
Save-Png $original (Join-Path $assetsDir "Square44x44Logo.png") 44 44
Save-Png $original (Join-Path $assetsDir "Square71x71Logo.png") 71 71
Save-Png $original (Join-Path $assetsDir "Square150x150Logo.png") 150 150
Save-Png $original (Join-Path $assetsDir "Square310x310Logo.png") 310 310
Save-Png $original (Join-Path $assetsDir "SplashScreen.png") 620 300
Save-Png $original (Join-Path $assetsDir "Wide310x150Logo.png") 310 150

$original.Dispose()
Write-Host "Done."
