# Overlay contrast e2e: StickerContrast + show_source + COVER_OK.
param(
  [int]$TimeoutSec = 20,
  [int]$E2eSec = 10
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Exe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\overlay-contrast-e2e.md"
if (-not (Test-Path $Exe)) { throw "missing $Exe — build lenstrans_overlay" }
$args = @("--e2e-sec", "$E2eSec", "--e2e-stable", "--e2e-contrast", "--no-onboard")
$p = Start-Process -FilePath $Exe -ArgumentList $args -PassThru -NoNewWindow -Wait:$false
$ok = $p.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# Overlay e2e contrast (StickerContrast + show_source)",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- elapsed_ms: $($TimeoutSec * 1000)",
    "- cover_assert: NOT proven",
    "- detail: process killed after ${TimeoutSec}s"
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "OVERLAY_CONTRAST_E2E status=timeout"
  exit 3
}
if (-not (Test-Path $Out)) {
  Write-Host "OVERLAY_CONTRAST_E2E exit=$($p.ExitCode) missing $Out"
  exit 4
}
$md = Get-Content $Out -Raw
$cover = $md -match "COVER_OK"
$present = $md -match "PRESENT"
$contrast = $md -match "sticker\+contrast|saw_contrast:\s*yes"
Write-Host "OVERLAY_CONTRAST_E2E exit=$($p.ExitCode) cover=$cover present=$present contrast=$contrast"
if (-not ($cover -and $present -and $contrast)) { exit 2 }
exit 0
