# Makes the in-game icon from the artwork: crops the shield (no bronze frame, it is too fine
# at minimap size), resizes to 64x64 and writes an uncompressed 32-bit TGA, the texture format
# every WoW client reads. Usage (repo root):
#   powershell -ExecutionPolicy Bypass -File tools\make_icon.ps1 docs\curseforge\icon.png
param([string]$Source = "docs\curseforge\icon.png", [string]$Out = "ThreatHelperForever\Media\icon.tga")

Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
# The shield sits in the middle of the 1024 px artwork: keep a centred square of 70 %.
$side = [int]($src.Width * 0.70)
$x = [int](($src.Width - $side) / 2)
$y = [int](($src.Height - $side) / 2)
$size = 64
$bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $size, $size), $x, $y, $side, $side, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$src.Dispose()

# TGA header: no id, no colour map, type 2 (uncompressed true colour), 32 bpp, origin bottom-left.
$header = [byte[]](0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, ($size -band 255), ($size -shr 8), ($size -band 255), ($size -shr 8), 32, 8)
$pixels = New-Object byte[] ($size * $size * 4)
$i = 0
for ($row = $size - 1; $row -ge 0; $row--) {
    for ($col = 0; $col -lt $size; $col++) {
        $c = $bmp.GetPixel($col, $row)
        $pixels[$i] = $c.B; $pixels[$i + 1] = $c.G; $pixels[$i + 2] = $c.R; $pixels[$i + 3] = $c.A
        $i += 4
    }
}
$bmp.Dispose()
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$stream = [System.IO.File]::Create((Join-Path (Get-Location) $Out))
$stream.Write($header, 0, $header.Length)
$stream.Write($pixels, 0, $pixels.Length)
$stream.Close()
Write-Host "$Out written ($((Get-Item $Out).Length) bytes)"
