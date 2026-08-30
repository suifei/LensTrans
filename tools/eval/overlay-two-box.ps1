# Two-box overlay e2e: each box OCR+PRESENT+COVER_OK over fixture split regions.
param(
  [int]$TimeoutSec = 20,
  [int]$E2eSec = 12
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Exe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\overlay-two-box.md"
if (-not (Test-Path $Exe)) { throw "missing $Exe — build lenstrans_overlay" }
$args = @("--e2e-sec", "$E2eSec", "--e2e-two-box", "--no-onboard")
$p = Start-Process -FilePath $Exe -ArgumentList $args -PassThru -NoNewWindow -Wait:$false
$ok = $p.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# Overlay e2e two-box",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- elapsed_ms: $($TimeoutSec * 1000)",
    "- all_cover_ok: no",
    "- cover_assert: NOT proven",
    "- detail: process killed after ${TimeoutSec}s"
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "OVERLAY_TWO_BOX status=timeout"
  exit 3
}
if (-not (Test-Path $Out)) {
  Write-Host "OVERLAY_TWO_BOX exit=$($p.ExitCode) missing $Out"
  exit 4
}
$md = Get-Content $Out -Raw
$allOk = $md -match "all_cover_ok:\s*yes"
$box0 = $md -match "box 0[\s\S]*?cover_ok:\s*yes"
$box1 = $md -match "box 1[\s\S]*?cover_ok:\s*yes"
Write-Host "OVERLAY_TWO_BOX exit=$($p.ExitCode) all=$allOk box0=$box0 box1=$box1"
if (-not ($allOk -and $box0 -and $box1)) { exit 2 }
exit 0
