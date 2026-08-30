# Idle wake: overlay idle after HELLO, target text change -> OCR wake within 8s.
param(
  [int]$BootstrapSec = 2,
  [int]$IdleWaitSec = 3,
  [int]$WakeTimeoutSec = 8,
  [int]$WatchdogSec = 25
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TargetExe = Join-Path $Root "build\Release\lenstrans_e2e_target.exe"
$OverlayExe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$OutDir = Join-Path $Root "tools\eval\out"
$Md = Join-Path $OutDir "idle-wake.md"
$OverlayMd = Join-Path $OutDir "overlay-wgc-window.md"
$TargetOut = Join-Path $OutDir "e2e_target_idle_wake.txt"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path $TargetExe)) { throw "missing $TargetExe" }
if (-not (Test-Path $OverlayExe)) { throw "missing $OverlayExe" }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IdleWakeWin {
  public const uint WM_APP = 0x8000;
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

function Stop-All {
  param([System.Diagnostics.Process]$ov, [System.Diagnostics.Process]$tg)
  foreach ($p in @($ov, $tg)) {
    if ($p -and -not $p.HasExited) {
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
  }
}

function Read-Text([string]$path) {
  if (-not (Test-Path $path)) { return "" }
  return (Get-Content $path -Raw -ErrorAction SilentlyContinue)
}

function Test-HelloBootstrap([string]$log) {
  return ($log -match 'OCR text="HELLO Settings"') -and
         ($log -match 'PRESENT mode=') -and
         ($log -match 'COVER_OK')
}

function Test-PleaseWaitWake([string]$log) {
  $ocr = $log -match 'OCR text="Please wait"'
  $present = $log -match 'PRESENT mode=.*src="Please wait"'
  $cover = $log -match 'COVER_OK'
  return @{ ocr = [bool]$ocr; present = [bool]$present; cover = [bool]$cover; pass = ($ocr -and $present -and $cover) }
}

$target = $null
$overlay = $null
$rect = $null
$targetHwndPtr = [IntPtr]::Zero
$detail = ""
$helloReady = $false
$switched = $false
$wake = @{ ocr = $false; present = $false; cover = $false; pass = $false }
$wakeMs = $null
$switchAt = $null
$watchStart = Get-Date

try {
  if (Test-Path $TargetOut) { Remove-Item $TargetOut -Force }
  if (Test-Path $OverlayMd) { Remove-Item $OverlayMd -Force }

  $target = Start-Process -FilePath $TargetExe -PassThru -NoNewWindow -RedirectStandardOutput $TargetOut
  $deadline = [DateTime]::UtcNow.AddSeconds(8)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($target.HasExited) { break }
    $text = Read-Text $TargetOut
    if ($text -match 'E2E_TARGET rect=(\d+),(\d+),(\d+),(\d+)') {
      $rect = "$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4])"
    }
    if ($text -match 'hwnd=([0-9A-Fa-f]+)') {
      $targetHwndPtr = [IntPtr]::new([Convert]::ToInt64($Matches[1], 16))
    }
    if ($rect -and $targetHwndPtr -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 150
  }
  if (-not $rect) { throw "e2e_target did not print rect within 8s" }

  Start-Sleep -Milliseconds 400
  $runSec = $BootstrapSec + $IdleWaitSec + $WakeTimeoutSec + 8
  $overlayLifeSec = [math]::Min($runSec, $WatchdogSec - 1)
  $overlayArgs = @(
    "--e2e-wgc-window", "--e2e-sec", "$overlayLifeSec", "--e2e-stable", "--no-onboard",
    "--rect", $rect
  )
  $overlay = Start-Process -FilePath $OverlayExe -ArgumentList $overlayArgs -PassThru -WindowStyle Minimized
  $overlayStart = Get-Date

  # Bootstrap window: allow HELLO PRESENT/COVER (timed; overlay log only on exit)
  $bootstrapWait = $BootstrapSec + $IdleWaitSec
  $bootstrapEnd = $overlayStart.AddSeconds($bootstrapWait)
  while ((Get-Date) -lt $bootstrapEnd) {
    if (((Get-Date) - $watchStart).TotalSeconds -ge $WatchdogSec) {
      $detail = "watchdog ${WatchdogSec}s before switch"
      break
    }
    if ($overlay.HasExited) {
      $detail = "overlay exited before switch code=$($overlay.ExitCode)"
      break
    }
    Start-Sleep -Milliseconds 200
  }
  $helloReady = -not $detail

  # Switch target text via PostMessage WM_APP (F2 hotkey also supported)
  if ($helloReady) {
    $switchAt = Get-Date
    if ($targetHwndPtr -ne [IntPtr]::Zero) {
      [IdleWakeWin]::SetForegroundWindow($targetHwndPtr) | Out-Null
      [IdleWakeWin]::PostMessage($targetHwndPtr, [IdleWakeWin]::WM_APP, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
    $switchDeadline = [DateTime]::UtcNow.AddSeconds(2)
    while ([DateTime]::UtcNow -lt $switchDeadline) {
      if ((Read-Text $TargetOut) -match 'switched text=Please wait') {
        $switched = $true
        break
      }
      Start-Sleep -Milliseconds 100
    }
    if (-not $switched) {
      $detail = "PostMessage WM_APP did not switch target text within 2s"
      $helloReady = $false
    }
  }

  # Wait wake window, then let overlay exit naturally (WriteE2eArtifacts on --e2e-sec)
  if ($helloReady -and $switched) {
    $wakeEnd = $switchAt.AddSeconds($WakeTimeoutSec)
    while ((Get-Date) -lt $wakeEnd) {
      if (((Get-Date) - $watchStart).TotalSeconds -ge $WatchdogSec) {
        $detail = "watchdog ${WatchdogSec}s during wake window"
        break
      }
      if ($overlay.HasExited) { break }
      Start-Sleep -Milliseconds 200
    }
    if ($overlay -and -not $overlay.HasExited) {
      $remain = ($overlayStart.AddSeconds($overlayLifeSec) - (Get-Date)).TotalMilliseconds
      if ($remain -gt 0) {
        $overlay.WaitForExit([int][math]::Min($remain + 2000, ($WatchdogSec * 1000))) | Out-Null
      }
      if (-not $overlay.HasExited) {
        Stop-Process -Id $overlay.Id -Force -ErrorAction SilentlyContinue
        $overlay.WaitForExit(2000) | Out-Null
        if (-not $detail) { $detail = "overlay killed after e2e-sec wait" }
      }
    }
    Start-Sleep -Milliseconds 300
    $logFinal = Read-Text $OverlayMd
    $wake = Test-PleaseWaitWake $logFinal
    if ($wake.pass) {
      $wakeMs = [int](((Get-Date) - $switchAt).TotalMilliseconds)
    } elseif (-not $detail) {
      $bootstrapOk = Test-HelloBootstrap $logFinal
      if (-not $bootstrapOk) {
        $detail = "overlay md missing HELLO bootstrap"
      } else {
        $partial = ($wake.ocr -and -not $wake.present)
        $detail = if ($partial) {
          "partial wake: DIFF+OCR Please wait seen, but no PRESENT src=Please wait (committed HELLO blocks pipeline after idle)"
        } else {
          "no Please wait OCR+PRESENT+COVER within ${WakeTimeoutSec}s after switch"
        }
      }
    }
  }

  $logFinal = if ($logFinal) { $logFinal } else { Read-Text $OverlayMd }
  if ($logFinal) { $helloReady = Test-HelloBootstrap $logFinal }

  $utf8 = New-Object System.Text.UTF8Encoding $false
  $tail = if ($logFinal -and $logFinal.Length -gt 4000) { $logFinal.Substring($logFinal.Length - 4000) } else { $logFinal }
  if (-not $tail) { $tail = "(no overlay md captured)" }

  $lines = @(
    "# Idle wake (Watching, e2e_target text change)",
    "",
    "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "- status: $(if ($wake.pass) { '**pass**' } else { '**fail**' })",
    "- command: ``$OverlayExe --e2e-wgc-window --e2e-sec $overlayLifeSec --e2e-stable --no-onboard --rect $rect``",
    "- target_switch: PostMessage WM_APP (F2 hotkey also supported)",
    "- bootstrap_wait_s: $BootstrapSec + idle_wait_s: $IdleWaitSec",
    "- wake_timeout_s: $WakeTimeoutSec",
    "- watchdog_s: $WatchdogSec",
    "",
    "## Bootstrap",
    "",
    "- hello_present_cover: $(if ($helloReady) { '**yes**' } else { '**no**' })",
    "- target_switched: $(if ($switched) { '**yes**' } else { '**no**' })",
    "",
    "## Wake",
    "",
    "- woke: $(if ($wake.pass) { '**yes**' } else { '**no**' })",
    "- wake_ms: $(if ($null -ne $wakeMs) { $wakeMs } else { '-' })",
    "- ocr_please_wait: $(if ($wake.ocr) { 'yes' } else { 'no' })",
    "- present_please_wait: $(if ($wake.present) { 'yes' } else { 'no' })",
    "- cover_ok: $(if ($wake.cover) { 'yes' } else { 'no' })",
    "- new_ocr_text: $(if ($wake.ocr) { 'Please wait' } else { '-' })",
    "",
    "## Verdict",
    "",
    "- idle_wake: $(if ($wake.pass) { '**pass**' } else { '**fail**' })",
    "- detail: $(if ($detail) { $detail } else { if ($wake.pass) { 'Please wait OCR+PRESENT+COVER seen' } else { 'wake assertion failed' } })",
    "- goal_complete: **no**",
    "",
    "## Console (from overlay-wgc-window.md tail)",
    "",
    '```',
    $tail,
    '```'
  )
  [System.IO.File]::WriteAllLines($Md, $lines, $utf8)
  $lines | ForEach-Object { Write-Host $_ }

  if (-not $wake.pass) { exit 1 }
  exit 0
}
finally {
  Stop-All $overlay $target
}
