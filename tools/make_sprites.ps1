# Generates the character sprites (wizards, Shield Mage, ghost, training dummy) as PNGs from the text grids below.
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

# Walk cycle, 16x24: same body as idle; only the feet (rows 21-23) change.
# Stride (feet apart) -> passing (feet together) -> stride -> passing.
$hem = ".OBBBBBBBBBBO.T."  # hem stays put; only the feet move
$strideFeet  = @(".OKKO....OKKO.T.", ".OKKKO...OKKKOT.", ".OOOOO...OOOOO..")
$passingFeet = @("....OKKKKO....T.", "....OKKKKKO...T.", "....OOOOOOO.....")
$wizardWalk1 = $wizard[0..19] + @($hem) + $strideFeet
$wizardWalk2 = $wizard[0..19] + @($hem) + $passingFeet
$wizardWalk3 = $wizard[0..19] + @($hem) + $strideFeet
$wizardWalk4 = $wizard[0..19] + @($hem) + $passingFeet

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
# Shield Mage (docs/CHARACTERS.md): a hooded, bearded body in plate, a door
# shield in the left hand and the wizard's own staff in the right. Frames
# are built by stamping layers onto the body; '.' in a layer lets what's
# underneath show. A = steel, D = dark steel.
$mageBody = @(
    "................", "................", "....OOOOO.......", "...OHHHHHO......",
    "..OHHHHHHHO.....", "..OHHHHSSSO.....", "..OHHHSSSSO.....", "..OHHHSSSSO.....",
    "..OHHHWWWWO.....", ".OAAAAWWWAAO....", "OAAAAAAWAAAAO...", "ODAOHHHHHHOHO...",
    "ODAOHHHHHHOHO...", ".OOOBBBBBBOHO...", "...OHHHHHHOHHO..", "..OHHHHHHHHO....",
    "..OHHJHHHHHO....", "..OHHJHHHJHO....", ".OHHHJHHHJHHO...", ".OJJJJJJJJJJO...",
    ".ODDDDDDDDDDO...", "..OKKO..OKKO....", "..OKKKO.OKKKO...", "..OOOOO.OOOOO..."
)
# Casting: like the wizard, the arm leaves the body at chest height and bends
# up to the raised hand, so there's no hand at the hip.
$mageBodyCast = $mageBody.Clone()
$mageBodyCast[11] = "ODAOHHHHHHO....."; $mageBodyCast[12] = "ODAOHHHHHHOHH..."
$mageBodyCast[13] = ".OOOBBBBBBOOO..."; $mageBodyCast[14] = "...OHHHHHHO....."
# Walk cycle: exactly the wizard's feet (rows 21-23), swapped in whole.
$mageStride  = @(".OKKO....OKKO...", ".OKKKO...OKKKO..", ".OOOOO...OOOOO..")
$magePassing = @("....OKKKKO......", "....OKKKKKO.....", "....OOOOOOO.....")

# 13 tall, so at rest it ends on the armour skirt (row 20) and the feet show.
$mageShield = @(
    "OOOOOOOO", "OAAAAAAO", "OARRRRAO", "OARBBRAO", "OARBBRAO", "OABBBBAO",
    "OABBBBAO", "OARBBRAO", "OARRRRAO", "OAQQQQAO", "OAAAAAAO", "ODDDDDDO",
    "OOOOOOOO"
)
# The wizard's staff and hand: columns 12-15 of its frames, with the robe
# sleeve (R) recoloured to the mage's cloth (H).
function Get-Staff($grid) {
    $out = @()
    foreach ($row in $grid) {
        $s = ""
        foreach ($c in $row.Substring(12, 4).ToCharArray()) {
            $s += $(if ("LGTS".Contains([string]$c)) { $c } elseif ($c -eq 'R') { 'H' } else { '.' })
        }
        $out += $s
    }
    return , $out
}
# Stamp layers @(grid, x, y) onto a blank w x h canvas; returns row strings.
function New-Frame($w, $h, $layers) {
    $g = New-Object 'char[][]' $h
    for ($r = 0; $r -lt $h; $r++) { $g[$r] = ('.' * $w).ToCharArray() }
    foreach ($l in $layers) {
        $grid, $x, $y = $l
        for ($j = 0; $j -lt $grid.Count; $j++) {
            $line = [string]$grid[$j]
            for ($i = 0; $i -lt $line.Length; $i++) { if ($line[$i] -ne '.') { $g[$y + $j][$x + $i] = $line[$i] } }
        }
    }
    return , @($g | ForEach-Object { -join $_ })
}
$staffIdle = Get-Staff $wizard
$staffCast = Get-Staff $wizardCast
$staffWalk = Get-Staff $wizardWalk1 # same staff as idle
# Shield bottom: row 20 at rest (on the armour skirt, feet showing), raised
# 7 px and swung to the front to parry (so the mage keeps facing the foe).
$mageFrames = [ordered]@{
    ""        = New-Frame 16 24 (@(, @($mageBody, 0, 0)) + @(, @($staffIdle, 12, 0)) + @(, @($mageShield, 0, 8)))
    "_cast"   = New-Frame 16 28 (@(, @($mageBodyCast, 0, 4)) + @(, @($staffCast, 12, 0)) + @(, @($mageShield, 0, 12)))
    "_parry"  = New-Frame 16 24 (@(, @($mageBody, 0, 0)) + @(, @($staffIdle, 12, 0)) + @(, @($mageShield, 8, 3)))
}
# Walk cycle like the wizard's: stride, passing, stride, passing.
foreach ($f in 1..4) {
    $feet = if ($f % 2 -eq 1) { $mageStride } else { $magePassing }
    $walkBody = $mageBody[0..20] + $feet
    $mageFrames["_walk$f"] = New-Frame 16 24 (@(, @($walkBody, 0, 0)) + @(, @($staffWalk, 12, 0)) + @(, @($mageShield, 0, 8)))
}

# Ghost, 16x24: who you are in the training room before walking into a
# character. Floats (rows 20-23 empty, above its shadow); the walk cycle
# only waves the tail. P = body, Y = shade.
$ghostBody = @(
    "................", "................", "................", "................",
    "......OOOO......", "....OOPPPPOO....", "...OPPPPPPPPO...", "..OPPPPPPPPPPO..",
    "..OPPPPPEPPEPO..", "..OPPPPPEPPEPO..", "..OPPPPPPPPPPO..", "..OYPPPPPPPPPO..",
    "..OYPPPPPPPPPO..", "..OYPPPPPPPPPO..", "..OYYPPPPPPPPO..", "..OYYPPPPPPPYO..",
    "..OYYYPPPPPYYO.."
)
$ghostTailA = @("..OYYYYYYYYYYO..", "..OYO.OYYO.OYO..", "...O...OO...O...")
$ghostTailB = @("..OYYYYYYYYYYO..", "...OYO.OYO.OYO..", "....O...O...O...")
$ghostEnd = @("................", "................", "................", "................")
$ghostA = $ghostBody + $ghostTailA + $ghostEnd
$ghostB = $ghostBody + $ghostTailB + $ghostEnd
$ghostFrames = [ordered]@{ "" = $ghostA; "_cast" = $ghostA;
    "_walk1" = $ghostA; "_walk2" = $ghostB; "_walk3" = $ghostA; "_walk4" = $ghostB }

$shared = @{
    O = "#1a1c2c"   # outline
    S = "#f4c8a0"   # skin
    E = "#1a1c2c"   # eye
    W = "#f4f4f4"   # beard
    B = "#ffcd75"   # gold trim
    K = "#333c57"   # boots
    T = "#8b5a2b"   # staff wood
    L = "#f4f4f4"   # gem highlight
    A = "#94b0c2"   # steel (Shield Mage)
    D = "#566c86"   # dark steel (Shield Mage)
}

# Per-character frames and colours. Wizards: H/J hat, R/Q robe, G gem.
# Dummy: N/M burlap, P post, R/W target, G crystal.
$wizardFrames = [ordered]@{ "" = $wizard; "_cast" = $wizardCast;
    "_walk1" = $wizardWalk1; "_walk2" = $wizardWalk2; "_walk3" = $wizardWalk3; "_walk4" = $wizardWalk4 }
$characters = [ordered]@{
    wizard_blue = @{ frames = $wizardFrames; colors = @{ H = "#3b5dc9"; J = "#29366f"; R = "#3b5dc9"; Q = "#29366f"; G = "#73eff7" } }
    wizard_red  = @{ frames = $wizardFrames; colors = @{ H = "#b13e53"; J = "#5d275d"; R = "#b13e53"; Q = "#5d275d"; G = "#a7f070" } }
    shieldmage_blue = @{ frames = $mageFrames; colors = @{ H = "#3b5dc9"; J = "#29366f"; R = "#3b5dc9"; Q = "#29366f"; G = "#73eff7" } }
    shieldmage_red  = @{ frames = $mageFrames; colors = @{ H = "#b13e53"; J = "#5d275d"; R = "#b13e53"; Q = "#5d275d"; G = "#a7f070" } }
    ghost           = @{ frames = $ghostFrames; colors = @{ P = "#f4f4f4"; Y = "#94b0c2" } }
    dummy      = @{ frames = [ordered]@{ "" = $dummy; "_cast" = $dummyCast }
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
