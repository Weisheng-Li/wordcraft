# Generates the character sprites (wizards, training dummy) as PNGs from the text grids below.
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

# Training dummy, 16x24: sack head, crossbar arms with straw ends, target
# on the chest, post and base. M = dark burlap (stitches).
$dummy = @(
    "................",
    ".....OOOOOO.....",
    "....ONNNNNNO....",
    "....ONMNNMNO....",
    "....ONNNNNNO....",
    "....ONNMMNNO....",
    ".....ONNNNO.....",
    "......OPPO......",
    "..OOOOOPPOOOOO..",
    ".BPPPPPPPPPPPPB.",
    "..OOOONNNNNNOO..",
    ".....ONWWWWNO...",
    ".....ONWRRWNO...",
    ".....ONWRRWNO...",
    ".....ONWWWWNO...",
    ".....ONNNNNNO...",
    ".....ONNMMNNO...",
    "......OOPPOO....",
    ".......OPPO.....",
    ".......OPPO.....",
    ".......OPPO.....",
    ".......OPPO.....",
    ".....OOOPPOOO...",
    "....OKKKKKKKKO.."
)

# Dummy casting frame, 16x28: holds up a stick with a red crystal. The
# crystal sits where the wizard's gem does (col 14, row 3).
$dummyCast = @(
    "................",
    "................",
    "..............L.",
    ".............GLG",
    "..............G.",
    ".....OOOOOO...T.",
    "....ONNNNNNO..T.",
    "....ONMNNMNO..T.",
    "....ONNNNNNO..T.",
    "....ONNMMNNO..T.",
    ".....ONNNNO...T.",
    "......OPPO....T.",
    "..OOOOOPPOOOOOT.",
    ".BPPPPPPPPPPPPB."
) + $dummy[10..23]


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

# Per-character frames and colours. Wizards: H/J hat, R/Q robe, G gem.
# Dummy: N/M burlap, P post, R/W target, G crystal.
$wizardFrames = [ordered]@{ "" = $wizard; "_cast" = $wizardCast }
$characters = [ordered]@{
    wizard_blue = @{ frames = $wizardFrames; colors = @{ H = "#3b5dc9"; J = "#29366f"; R = "#3b5dc9"; Q = "#29366f"; G = "#73eff7" } }
    wizard_red  = @{ frames = $wizardFrames; colors = @{ H = "#b13e53"; J = "#5d275d"; R = "#b13e53"; Q = "#5d275d"; G = "#a7f070" } }
    dummy       = @{ frames = [ordered]@{ "" = $dummy; "_cast" = $dummyCast }
                     colors = @{ N = "#d8b47a"; M = "#9c7a4a"; P = "#8b5a2b"; R = "#e43b44"; W = "#f4f4f4"; G = "#e43b44" } }
}

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root "assets\sprites"
foreach ($name in $characters.Keys) {
    $palette = $shared.Clone()
    $colors = $characters[$name].colors
    foreach ($k in $colors.Keys) { $palette[$k] = $colors[$k] }
    $frames = $characters[$name].frames

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
