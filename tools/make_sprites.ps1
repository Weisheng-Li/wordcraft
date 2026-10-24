# Generates the wizard sprites as PNGs from the text grid below.
# Run from the project root:  powershell -ExecutionPolicy Bypass -File tools\make_sprites.ps1
# Optional: -PreviewDir <dir> also writes 10x-scaled copies for easy viewing.
param([string]$PreviewDir)

Add-Type -AssemblyName System.Drawing

# 16x24, facing right. Each character is a palette key; '.' is transparent.
$wizard = @(
    "....OO..........",
    "...OHHO.........",
    "....OHHO........",
    "....OHHHO.......",
    "...OHHJHHO......",
    "...OHHHJHO....L.",
    "..OHHHHJHHO..GLG",
    "..OBBBBBBBBO..G.",
    ".OHHHHHHHHHHO.T.",
    "..OOSSSSSEO...T.",
    "...OSSSSSSO...T.",
    "...OWWSSWWO...T.",
    "..ORRWWWWWRO..T.",
    ".ORRRWWWWRRRO.T.",
    ".ORRRRWWRRRROSTS",
    ".ORQRRRRRRRRO.T.",
    ".ORQRRRRRRRRO.T.",
    ".ORQRRRRRRRQO.T.",
    ".ORQRRRRRRRQO.T.",
    ".ORQRRRRRRRQO.T.",
    ".OBBBBBBBBBBO.T.",
    "..OKKO..OKKO..T.",
    "..OKKKO.OKKKO.T.",
    "..OOOOO.OOOOO..."
)

# Casting pose, 16x28: same body with the staff raised overhead. 4 rows
# taller than idle so the gem clears the hat. Gem centre is at col 14, row 3
# (render.lua's CAST_GEM must match).
$wizardCast = @(
    "................",
    "................",
    "..............L.",
    ".............GLG",
    "....OO........G.",
    "...OHHO.......T.",
    "....OHHO......T.",
    "....OHHHO.....T.",
    "...OHHJHHO....T.",
    "...OHHHJHO....T.",
    "..OHHHHJHHO...T.",
    "..OBBBBBBBBO..T.",
    ".OHHHHHHHHHHO.T.",
    "..OOSSSSSEO...T.",
    "...OSSSSSSO..STS",
    "...OWWSSWWO..RT.",
    "..ORRWWWWWRORRT.",
    ".ORRRWWWWRRRO.T.",
    ".ORRRRWWRRRRO...",
    ".ORQRRRRRRRRO...",
    ".ORQRRRRRRRRO...",
    ".ORQRRRRRRRQO...",
    ".ORQRRRRRRRQO...",
    ".ORQRRRRRRRQO...",
    ".OBBBBBBBBBBO...",
    "..OKKO..OKKO....",
    "..OKKKO.OKKKO...",
    "..OOOOO.OOOOO..."
)

# Output file suffix -> grid.
$frames = [ordered]@{ "" = $wizard; "_cast" = $wizardCast }

# Colours shared by every wizard.
$shared = @{
    O = "#1a1c2c"   # outline
    S = "#f4c8a0"   # skin
    E = "#1a1c2c"   # eye
    W = "#f4f4f4"   # beard
    B = "#ffcd75"   # gold trim
    K = "#333c57"   # boots
    T = "#8b5a2b"   # staff wood
    L = "#f4f4f4"   # gem highlight
}

# Per-wizard colours: H/J hat, R/Q robe, G gem.
$variants = @{
    wizard_blue = @{ H = "#3b5dc9"; J = "#29366f"; R = "#3b5dc9"; Q = "#29366f"; G = "#73eff7" }
    wizard_red  = @{ H = "#b13e53"; J = "#5d275d"; R = "#b13e53"; Q = "#5d275d"; G = "#a7f070" }
}

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "assets\sprites"
foreach ($name in $variants.Keys) {
    $palette = $shared.Clone()
    foreach ($k in $variants[$name].Keys) { $palette[$k] = $variants[$name][$k] }

    foreach ($suffix in $frames.Keys) {
        $grid = $frames[$suffix]
        $file = "$name$suffix"
        $w = $grid[0].Length
        $h = $grid.Count

        $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        for ($y = 0; $y -lt $h; $y++) {
            $row = $grid[$y]
            if ($row.Length -ne $w) { throw "$file row $y is $($row.Length) wide, expected $w" }
            for ($x = 0; $x -lt $w; $x++) {
                $c = [string]$row[$x]
                if ($c -eq ".") {
                    $bmp.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
                } elseif ($palette.ContainsKey($c)) {
                    $bmp.SetPixel($x, $y, [System.Drawing.ColorTranslator]::FromHtml($palette[$c]))
                } else {
                    throw "Unknown palette key '$c' in $file at row $y, col $x"
                }
            }
        }

        $bmp.Save((Join-Path $outDir "$file.png"), [System.Drawing.Imaging.ImageFormat]::Png)

        if ($PreviewDir) {
            $scale = 10
            $big = New-Object System.Drawing.Bitmap ($w * $scale), ($h * $scale)
            $g = [System.Drawing.Graphics]::FromImage($big)
            $g.Clear([System.Drawing.ColorTranslator]::FromHtml("#94b0c2"))
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
            $g.DrawImage($bmp, 0, 0, $w * $scale, $h * $scale)
            $big.Save((Join-Path $PreviewDir "$file.png"), [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose(); $big.Dispose()
        }
        $bmp.Dispose()
        Write-Output "Wrote assets\sprites\$file.png"
    }
}
