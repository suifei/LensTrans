# WM_HOTKEY internal probe: overlay --e2e-hotkey-probe toggles WS_EX_TRANSPARENT via PostMessage.
param(
  [int]$TimeoutSec = 15
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OverlayExe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\hotkey-probe.md"
$OutDir = Split-Path $Out
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path $OverlayExe)) { throw "missing $OverlayExe — build lenstrans_overlay" }

$started = Get-Date
$overlay = $null
$pass = $false
$detail = ""

try {
  $p = Start-Process -FilePath $OverlayExe -ArgumentList @("--e2e-hotkey-probe", "--no-onboard") `
    -PassThru -NoNewWindow -Wait:$false
  $overlay = $p
  $ok = $p.WaitForExit($TimeoutSec * 1000)
  if (-not $ok) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $detail = "watchdog ${TimeoutSec}s"
  } else {
    $code = $p.ExitCode
    if (Test-Path $Out) {
      $md = Get-Content $Out -Raw
      $mdPass = ($md -match "status:\s*\*\*pass\*\*")
      if ($null -eq $code) { $code = $(if ($mdPass) { 0 } else { 1 }) }
      $pass = ($code -eq 0) -and $mdPass
      $detail = if ($pass) { "exit=0; hotkey-probe.md pass" } else { "exit=$code; md_pass=$mdPass" }
    } else {
      $detail = "missing hotkey-probe.md exit=$code"
    }
  }
} catch {
  $detail = $_.Exception.Message
} finally {
  if ($overlay -and -not $overlay.HasExited) {
    Stop-Process -Id $overlay.Id -Force -ErrorAction SilentlyContinue
  }
}

$elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
Write-Host "HOTKEY_PROBE status=$(if ($pass) { 'pass' } else { 'fail' }) elapsed=${elapsed}s detail=$detail"
exit $(if ($pass) { 0 } else { 1 })
