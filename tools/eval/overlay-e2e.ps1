# Overlay e2e: COVER_OK + PRESENT. Stable mode uses formal stab+debounce (fake engine only).
param(
  [int]$TimeoutSec = 22,
  [int]$E2eSec = 15,
  [switch]$Stable
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Exe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\overlay-e2e.md"
if (-not (Test-Path $Exe)) { throw "missing $Exe — build lenstrans_overlay" }
$args = @("--e2e-sec", "$E2eSec", "--no-onboard")
if ($Stable) { $args += "--e2e-stable" }
$p = Start-Process -FilePath $Exe -ArgumentList $args -PassThru -NoNewWindow -Wait:$false
$ok = $p.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $mode = if ($Stable) { "stable" } else { "fast" }
  $lines = @(
    "# Overlay e2e (cover source text)",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- mode: $mode",
    "- elapsed_ms: $($TimeoutSec * 1000)",
    "- cover_assert: NOT proven",
    "- detail: process killed after ${TimeoutSec}s"
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "OVERLAY_E2E status=timeout mode=$mode"
  exit 3
}
if (-not (Test-Path $Out)) {
  Write-Host "OVERLAY_E2E exit=$($p.ExitCode) missing $Out"
  exit 4
}
$md = Get-Content $Out -Raw
$cover = $md -match "COVER_OK"
$present = $md -match "PRESENT"
Write-Host "OVERLAY_E2E exit=$($p.ExitCode) cover=$cover present=$present stable=$Stable"
if (-not ($cover -and $present)) { exit 2 }
exit 0
