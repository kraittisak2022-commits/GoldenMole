# Generates a complete AppIcon.appiconset from the source logo for iPhone + iPad.
param(
    [string]$SourceImage = (Join-Path $PSScriptRoot "..\ios-swiftui\Resources\Assets.xcassets\AppIcon.appiconset\app_logo.png"),
    [string]$OutputDir = (Join-Path $PSScriptRoot "..\ios-swiftui\Resources\Assets.xcassets\AppIcon.appiconset")
)

Add-Type -AssemblyName System.Drawing

function New-SquareMasterImage {
    param([string]$Path)

    $source = [System.Drawing.Image]::FromFile($Path)
    try {
        $size = [Math]::Min($source.Width, $source.Height)
        $x = [int](($source.Width - $size) / 2)
        $y = [int](($source.Height - $size) / 2)

        $cropped = New-Object System.Drawing.Bitmap $size, $size
        $cropGraphics = [System.Drawing.Graphics]::FromImage($cropped)
        try {
            $cropGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $srcRect = New-Object System.Drawing.Rectangle $x, $y, $size, $size
            $dstRect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
            $cropGraphics.DrawImage($source, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        }
        finally {
            $cropGraphics.Dispose()
        }

        $bitmap = New-Object System.Drawing.Bitmap 1024, 1024
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.Clear([System.Drawing.Color]::FromArgb(255, 26, 26, 26))
            $graphics.DrawImage($cropped, 0, 0, 1024, 1024)
        }
        finally {
            $graphics.Dispose()
            $cropped.Dispose()
        }

        return $bitmap
    }
    finally {
        $source.Dispose()
    }
}

function Save-Icon {
    param(
        [System.Drawing.Image]$Master,
        [int]$PixelSize,
        [string]$FileName
    )

    $bitmap = New-Object System.Drawing.Bitmap $PixelSize, $PixelSize
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($Master, 0, 0, $PixelSize, $PixelSize)
    }
    finally {
        $graphics.Dispose()
    }

    $outPath = Join-Path $OutputDir $FileName
    $bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}

$iconSlots = @(
    @{ FileName = "Icon-20@2x.png";      Idiom = "iphone"; Scale = "2x"; Size = "20x20";   Pixels = 40 },
    @{ FileName = "Icon-20@3x.png";      Idiom = "iphone"; Scale = "3x"; Size = "20x20";   Pixels = 60 },
    @{ FileName = "Icon-29@2x.png";      Idiom = "iphone"; Scale = "2x"; Size = "29x29";   Pixels = 58 },
    @{ FileName = "Icon-29@3x.png";      Idiom = "iphone"; Scale = "3x"; Size = "29x29";   Pixels = 87 },
    @{ FileName = "Icon-40@2x.png";      Idiom = "iphone"; Scale = "2x"; Size = "40x40";   Pixels = 80 },
    @{ FileName = "Icon-40@3x.png";      Idiom = "iphone"; Scale = "3x"; Size = "40x40";   Pixels = 120 },
    @{ FileName = "Icon-60@2x.png";      Idiom = "iphone"; Scale = "2x"; Size = "60x60";   Pixels = 120 },
    @{ FileName = "Icon-60@3x.png";      Idiom = "iphone"; Scale = "3x"; Size = "60x60";   Pixels = 180 },
    @{ FileName = "Icon-20.png";         Idiom = "ipad";   Scale = "1x"; Size = "20x20";   Pixels = 20 },
    @{ FileName = "Icon-20@2x-ipad.png"; Idiom = "ipad";   Scale = "2x"; Size = "20x20";   Pixels = 40 },
    @{ FileName = "Icon-29.png";         Idiom = "ipad";   Scale = "1x"; Size = "29x29";   Pixels = 29 },
    @{ FileName = "Icon-29@2x-ipad.png"; Idiom = "ipad";   Scale = "2x"; Size = "29x29";   Pixels = 58 },
    @{ FileName = "Icon-40.png";         Idiom = "ipad";   Scale = "1x"; Size = "40x40";   Pixels = 40 },
    @{ FileName = "Icon-40@2x-ipad.png"; Idiom = "ipad";   Scale = "2x"; Size = "40x40";   Pixels = 80 },
    @{ FileName = "Icon-76.png";         Idiom = "ipad";   Scale = "1x"; Size = "76x76";   Pixels = 76 },
    @{ FileName = "Icon-76@2x.png";      Idiom = "ipad";   Scale = "2x"; Size = "76x76";   Pixels = 152 },
    @{ FileName = "Icon-83.5@2x.png";    Idiom = "ipad";   Scale = "2x"; Size = "83.5x83.5"; Pixels = 167 },
    @{ FileName = "Icon-1024.png";       Idiom = "ios-marketing"; Scale = "1x"; Size = "1024x1024"; Pixels = 1024 }
)

if (-not (Test-Path $SourceImage)) {
    throw "Source image not found: $SourceImage"
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$master = New-SquareMasterImage -Path $SourceImage
try {
    foreach ($slot in $iconSlots) {
        Save-Icon -Master $master -PixelSize $slot.Pixels -FileName $slot.FileName
    }
}
finally {
    $master.Dispose()
}

$images = $iconSlots | ForEach-Object {
    [ordered]@{
        filename = $_.FileName
        idiom    = $_.Idiom
        scale    = $_.Scale
        size     = $_.Size
    }
}

$contents = [ordered]@{
    images = @($images)
    info   = [ordered]@{
        author = "xcode"
        version = 1
    }
}

$contentsPath = Join-Path $OutputDir "Contents.json"
$contents | ConvertTo-Json -Depth 5 | Set-Content -Path $contentsPath -Encoding UTF8

Write-Host "Generated $($iconSlots.Count) app icons in $OutputDir"
