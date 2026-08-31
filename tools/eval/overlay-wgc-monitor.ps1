# Monitor-crop WGC overlay acceptance: e2e_target + overlay --rect (no CreateForWindow).
param(
  [int]$TimeoutSec = 45,
  [int]$E2eSec = 35
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TargetExe = Join-Path $Root "build\Release\lenstrans_e2e_target.exe"
$OverlayExe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\overlay-wgc-monitor.md"
$Model = Join-Path $Root "models\qwen2.5-1.5b-instruct-q4_k_m.gguf"
if (-not (Test-Path $TargetExe)) { throw "missing $TargetExe — build lenstrans_e2e_target" }
if (-not (Test-Path $OverlayExe)) { throw "missing $OverlayExe — build lenstrans_overlay" }

$stdoutPath = Join-Path $Root "tools\eval\out\e2e_target_rect.txt"
if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }
$target = Start-Process -FilePath $TargetExe -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath
$rect = $null
$deadline = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $deadline) {
  if ($target.HasExited) { break }
  if (Test-Path $stdoutPath) {
    $text = Get-Content $stdoutPath -Raw -ErrorAction SilentlyContinue
    if ($text -match 'E2E_TARGET rect=(\d+),(\d+),(\d+),(\d+)') {
      $rect = "$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4])"
      break
    }
  }
  Start-Sleep -Milliseconds 200
}
if (-not $rect) {
  Stop-Process -Id $target.Id -Force -ErrorAction SilentlyContinue
  throw "e2e_target did not print rect within 8s"
}
Start-Sleep -Milliseconds 400

$overlayArgs = @("--e2e-wgc-monitor", "--e2e-sec", "$E2eSec", "--no-onboard", "--rect", $rect)
if (Test-Path $Model) { $overlayArgs += "--e2e-llama" } else { $overlayArgs += "--e2e-stable" }
$overlay = Start-Process -FilePath $OverlayExe -ArgumentList $overlayArgs -PassThru -NoNewWindow -Wait:$false

$all = @($target.Id, $overlay.Id)
$ok = $overlay.WaitForExit($TimeoutSec * 1000)
foreach ($procId in $all) {
  Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
}

if (-not $ok) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# Overlay WGC monitor crop",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- target_rect: $rect",
    "- wgc_capture: unknown",
    "- ocr_text: -",
    "- cover_assert: NOT proven",
    "- present: no",
    "- detail: killed after ${TimeoutSec}s"
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "OVERLAY_WGC_MONITOR status=timeout rect=$rect"
  exit 3
}
if (-not (Test-Path $Out)) {
  Write-Host "OVERLAY_WGC_MONITOR exit=$($overlay.ExitCode) missing $Out"
  exit 4
}
$md = Get-Content $Out -Raw
$wgc = $md -match "wgc_capture:\s*\*\*yes\*\*"
$cover = $md -match "COVER_OK"
$present = $md -match "saw_present:\s*yes"
$ocr = $md -match "HELLO Settings"
Write-Host "OVERLAY_WGC_MONITOR exit=$($overlay.ExitCode) wgc=$wgc cover=$cover present=$present ocr=$ocr rect=$rect"
if (-not ($wgc -and $cover -and $present -and $ocr)) { exit 2 }
exit 0
