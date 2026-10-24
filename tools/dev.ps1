# Dev loop: runs the game and restarts it when .dev/restart is touched.
# Restarts are explicit (not on every file save) so a half-finished batch of
# edits never launches. After your own edits, press F5 in the game instead.
#   powershell -ExecutionPolicy Bypass -File tools\dev.ps1
# Trigger a restart from another shell:
#   powershell -File tools\restart.ps1

$root = Split-Path -Parent $PSScriptRoot
$love = "C:\Program Files\LOVE\lovec.exe"
$trigger = Join-Path $root ".dev\restart"

New-Item -ItemType Directory -Force (Split-Path $trigger) | Out-Null
if (-not (Test-Path $trigger)) { New-Item -ItemType File $trigger | Out-Null }

function Get-Stamp { (Get-Item $trigger).LastWriteTimeUtc.Ticks }

function Start-Game {
    Write-Host "[dev] starting game" -ForegroundColor Cyan
    Start-Process $love -ArgumentList "." -WorkingDirectory $root -NoNewWindow -PassThru
}

$game = Start-Game
$stamp = Get-Stamp
$closedNoticeShown = $false

try {
    while ($true) {
        Start-Sleep -Milliseconds 300
        $now = Get-Stamp
        if ($now -ne $stamp) {
            $stamp = $now
            Write-Host "[dev] restart requested" -ForegroundColor Yellow
            if ($game -and -not $game.HasExited) { Stop-Process -Id $game.Id -Force }
            $game = Start-Game
            $closedNoticeShown = $false
        } elseif ($game.HasExited -and -not $closedNoticeShown) {
            Write-Host "[dev] game closed; it will start again on the next restart request" -ForegroundColor DarkGray
            $closedNoticeShown = $true
        }
    }
} finally {
    if ($game -and -not $game.HasExited) { Stop-Process -Id $game.Id -Force }
}
