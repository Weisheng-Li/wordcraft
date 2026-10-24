# Ask a running tools\dev.ps1 to restart the game.
$trigger = Join-Path (Split-Path -Parent $PSScriptRoot) ".dev\restart"
New-Item -ItemType Directory -Force (Split-Path $trigger) | Out-Null
if (Test-Path $trigger) { (Get-Item $trigger).LastWriteTime = Get-Date }
else { New-Item -ItemType File $trigger | Out-Null }
