# Overlay e2e with real LocalEngine (Qwen2.5-1.5B). Watchdog 45s incl. model load.
param(
  [int]$TimeoutSec = 45,
  [int]$E2eSec = 35
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Exe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\overlay-llama-e2e.md"
if (-not (Test-Path $Exe)) { throw "missing $Exe — build lenstrans_overlay" }
$args = @("--e2e-sec", "$E2eSec", "--e2e-llama", "--no-onboard")
$p = Start-Process -FilePath $Exe -ArgumentList $args -PassThru -NoNewWindow -Wait:$false
$ok = $p.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# Overlay e2e llama (LocalEngine Qwen2.5-1.5B)",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- elapsed_ms: $($TimeoutSec * 1000)",
    "- cover_assert: NOT proven",
    "- detail: process killed after ${TimeoutSec}s (incl. model load budget)"
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "OVERLAY_LLAMA_E2E status=timeout"
  exit 3
}
if (-not (Test-Path $Out)) {
  Write-Host "OVERLAY_LLAMA_E2E exit=$($p.ExitCode) missing $Out"
  exit 4
}
$md = Get-Content $Out -Raw
$cover = $md -match "COVER_OK"
$present = $md -match "PRESENT"
Write-Host "OVERLAY_LLAMA_E2E exit=$($p.ExitCode) cover=$cover present=$present"
if (-not ($cover -and $present)) { exit 2 }
exit 0
