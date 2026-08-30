# Click-through acceptance: overlay Watching (WS_EX_TRANSPARENT) over e2e_target; SendInput click.
param(
  [int]$TimeoutSec = 15
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TargetExe = Join-Path $Root "build\Release\lenstrans_e2e_target.exe"
$OverlayExe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\click-through.md"
$OutDir = Split-Path $Out
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path $TargetExe)) { throw "missing $TargetExe — build lenstrans_e2e_target" }
if (-not (Test-Path $OverlayExe)) { throw "missing $OverlayExe — build lenstrans_overlay" }

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinClickThrough {
  public const int GWL_EXSTYLE = -20;
  public const uint WS_EX_TRANSPARENT = 0x00000020;
  public const uint INPUT_MOUSE = 0;
  public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
  public const uint MOUSEEVENTF_LEFTUP = 0x0004;

  public delegate bool EnumProc(IntPtr h, IntPtr l);

  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)] public struct InputUnion { [FieldOffset(0)] public MOUSEINPUT mi; }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
    public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
  }

  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] p, int cb);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lp, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);

  public static IntPtr OverlayHwnd = IntPtr.Zero;

  public static bool EnumAll(IntPtr h, IntPtr l) {
    var sb = new StringBuilder(256);
    GetClassName(h, sb, sb.Capacity);
    if (sb.ToString() == "LensTransOverlayPoC") OverlayHwnd = h;
    return true;
  }

  public static void RefreshOverlay() {
    OverlayHwnd = IntPtr.Zero;
    EnumWindows(EnumAll, IntPtr.Zero);
  }

  public static bool IsClickThrough(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) return false;
    return (GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TRANSPARENT) != 0;
  }

  public static IntPtr HitTestAt(int x, int y) {
    var p = new POINT { X = x, Y = y };
    return WindowFromPoint(p);
  }

  public static uint SendClick(int x, int y, bool focusTarget, IntPtr targetHwnd) {
    if (focusTarget && targetHwnd != IntPtr.Zero) SetForegroundWindow(targetHwnd);
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(80);
    INPUT[] ins = new INPUT[2];
    ins[0].type = INPUT_MOUSE; ins[0].U.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    ins[1].type = INPUT_MOUSE; ins[1].U.mi.dwFlags = MOUSEEVENTF_LEFTUP;
    return SendInput(2, ins, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@

$started = Get-Date
$stdoutPath = Join-Path $OutDir "e2e_target_click.txt"
if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }
$target = $null
$overlay = $null
$rect = $null
$targetHwndHex = $null
$targetHwnd = [IntPtr]::Zero
$overlayTransparent = $false
$hitTestReady = $false
$lastHitHwndHex = $null
$clickAttempts = 0
$sendInputUnits = 0
$rx = 0; $ry = 0; $rw = 0; $rh = 0
$clicked = $false
$detail = ""
$status = "fail"

function Write-Report($pass) {
  $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# Click-through (Watching WS_EX_TRANSPARENT)",
    "",
    "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "- status: $(if ($pass) { '**pass**' } else { '**fail**' })",
    "- click_through: $(if ($pass) { '**yes**' } else { '**no**' })",
    "- target_rect: $(if ($rect) { $rect } else { '-' })",
    "- target_hwnd: $(if ($targetHwndHex) { $targetHwndHex } else { '-' })",
    "- click_at: $(if ($rect) { "$([int]($rx + $rw/2)),$([int]($ry + $rh/2))" } else { '-' })",
    "- saw_CLICKED: $(if ($clicked) { 'yes' } else { 'no' })",
    "- click_attempts: $clickAttempts",
    "- sendinput_units: $sendInputUnits",
    "- overlay_transparent: $(if ($overlayTransparent) { 'yes' } else { 'no' })",
    "- hit_test_ready: $(if ($hitTestReady) { 'yes' } else { 'no' })",
    "- last_hit_hwnd: $(if ($lastHitHwndHex) { $lastHitHwndHex } else { '-' })",
    "- overlay_mode: Watching (--e2e-wgc-window --e2e-stable --no-onboard --rect, no fixture)",
    "- elapsed_s: $elapsed",
    "- detail: $detail",
    "- goal_complete: **no**"
  )
  if (-not $pass) {
    $stdoutText = Read-TargetStdout
    if (-not $stdoutText) { $stdoutText = "-" }
    $exitText = "-"
    if ($target) {
      if ($target.HasExited) { $exitText = "$($target.ExitCode)" }
      else { $exitText = "running" }
    }
    $lines += "- target_exit: $exitText"
    $lines += "- target_stdout:"
    $lines += '```'
    foreach ($line in ($stdoutText -split "`r?`n")) { $lines += $line }
    $lines += '```'
  }
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
}

function Read-TargetStdout {
  if (-not (Test-Path $stdoutPath)) { return $null }
  return Get-Content $stdoutPath -Raw -ErrorAction SilentlyContinue
}

function Test-ClickedInStdout {
  $text = Read-TargetStdout
  return ($text -and $text -match '(?m)^CLICKED\s*$')
}

function Format-Hwnd([IntPtr]$hwnd) {
  if ($hwnd -eq [IntPtr]::Zero) { return "-" }
  return ("0x{0:X}" -f $hwnd.ToInt64())
}

function Wait-TargetReady([IntPtr]$hwnd, [int]$ms) {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($ms)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ([WinClickThrough]::IsWindow($hwnd) -and [WinClickThrough]::IsWindowVisible($hwnd)) {
      return $true
    }
    Start-Sleep -Milliseconds 80
  }
  return $false
}

function Wait-OverlayWatching([IntPtr]$expectedTarget, [int]$x, [int]$y, [int]$ms) {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($ms)
  while ([DateTime]::UtcNow -lt $deadline) {
    [WinClickThrough]::RefreshOverlay()
    $overlay = [WinClickThrough]::OverlayHwnd
    $hit = [WinClickThrough]::HitTestAt($x, $y)
    $script:lastHitHwndHex = Format-Hwnd $hit
    if ($overlay -ne [IntPtr]::Zero -and [WinClickThrough]::IsClickThrough($overlay) -and $hit -eq $expectedTarget) {
      return $true
    }
    Start-Sleep -Milliseconds 100
  }
  return $false
}

function Wait-ForClicked([int]$ms) {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($ms)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-ClickedInStdout) { return $true }
    Start-Sleep -Milliseconds 80
  }
  return $false
}

try {
  $target = Start-Process -FilePath $TargetExe -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath
  $deadline = [DateTime]::UtcNow.AddSeconds(8)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($target.HasExited) { break }
    $text = Read-TargetStdout
    if ($text) {
      if ($text -match 'E2E_TARGET rect=(\d+),(\d+),(\d+),(\d+)') {
        $rx = [int]$Matches[1]; $ry = [int]$Matches[2]; $rw = [int]$Matches[3]; $rh = [int]$Matches[4]
        $rect = "$rx,$ry,$rw,$rh"
      }
      if ($text -match 'hwnd=([0-9A-Fa-f]+)') {
        $targetHwndHex = "0x$($Matches[1])"
        $targetHwnd = [IntPtr]::new([Int64]::Parse($Matches[1], [System.Globalization.NumberStyles]::HexNumber))
      }
      if ($rect -and $targetHwnd -ne [IntPtr]::Zero) { break }
    }
    Start-Sleep -Milliseconds 150
  }
  if (-not $rect -or $targetHwnd -eq [IntPtr]::Zero) {
    $detail = "e2e_target did not print rect+hwnd within 8s"
    Write-Report $false
    Write-Host "CLICK_THROUGH status=fail reason=no_rect"
    exit 2
  }

  if (-not (Wait-TargetReady $targetHwnd 3000)) {
    $detail = "target hwnd $targetHwndHex not visible within 3s after rect printed"
    Write-Report $false
    Write-Host "CLICK_THROUGH status=fail reason=target_not_ready"
    exit 3
  }

  $cx = [int]($rx + $rw / 2)
  $cy = [int]($ry + $rh / 2)

  Start-Sleep -Milliseconds 300
  $overlayArgs = @(
    "--e2e-wgc-window", "--e2e-sec", "10", "--e2e-stable", "--no-onboard",
    "--rect", $rect, "--e2e-target-hwnd", $targetHwndHex
  )
  $overlay = Start-Process -FilePath $OverlayExe -ArgumentList $overlayArgs -PassThru -NoNewWindow -Wait:$false

  if (-not (Wait-OverlayWatching $targetHwnd $cx $cy 8000)) {
    [WinClickThrough]::RefreshOverlay()
    $overlayTransparent = [WinClickThrough]::IsClickThrough([WinClickThrough]::OverlayHwnd)
    $hitTestReady = ($lastHitHwndHex -eq $targetHwndHex)
    $detail = "overlay not ready within 8s: transparent=$overlayTransparent hit=$lastHitHwndHex expected=$targetHwndHex"
    Write-Report $false
    Write-Host "CLICK_THROUGH status=fail reason=overlay_not_watching"
    exit 4
  }

  [WinClickThrough]::RefreshOverlay()
  $overlayTransparent = [WinClickThrough]::IsClickThrough([WinClickThrough]::OverlayHwnd)
  $hitTestReady = $true
  Start-Sleep -Milliseconds 200

  if (-not (Wait-TargetReady $targetHwnd 3000)) {
    $detail = "target hwnd $targetHwndHex not visible before click"
    Write-Report $false
    Write-Host "CLICK_THROUGH status=fail reason=target_not_visible_before_click"
    exit 5
  }

  $maxAttempts = 3
  $sendInputOk = $false
  for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    $clickAttempts = $attempt
    $hit = [WinClickThrough]::HitTestAt($cx, $cy)
    $lastHitHwndHex = Format-Hwnd $hit
    if ($hit -ne $targetHwnd) {
      Start-Sleep -Milliseconds 150
      continue
    }
    $focusTarget = ($attempt -ge 2)
    $units = [WinClickThrough]::SendClick($cx, $cy, $focusTarget, $targetHwnd)
    $sendInputUnits += [int]$units
    if ($units -lt 2) {
      if ($attempt -lt $maxAttempts) { Start-Sleep -Milliseconds 300; continue }
      $detail = "SendInput failed after $maxAttempts attempts (last units=$units) at $cx,$cy"
      break
    }
    $sendInputOk = $true
    if (Wait-ForClicked 2000) {
      $clicked = $true
      break
    }
    if ($attempt -lt $maxAttempts) { Start-Sleep -Milliseconds 300 }
  }

  if ($clicked) {
    $status = "pass"
    $detail = "SendInput attempt $clickAttempts ($sendInputUnits units) at $cx,$cy; target stdout CLICKED"
  } elseif (-not $sendInputOk) {
    # detail already set on SendInput failure
  } elseif ($sendInputUnits -eq 0) {
    $detail = "SendInput blocked (0 units injected) at $cx,$cy; overlay transparent=$overlayTransparent hit=$lastHitHwndHex — run from interactive desktop"
  } else {
    $detail = "no CLICKED after $maxAttempts SendInput attempts ($sendInputUnits units) at $cx,$cy (transparent=$overlayTransparent hit=$lastHitHwndHex)"
  }
} catch {
  $detail = "exception: $($_.Exception.Message)"
} finally {
  foreach ($proc in @($overlay, $target)) {
    if ($proc -and -not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  }
}

$elapsedTotal = ((Get-Date) - $started).TotalSeconds
if ($elapsedTotal -gt $TimeoutSec) {
  if ($clicked) {
    $detail = "watchdog ${TimeoutSec}s exceeded but CLICKED seen; $detail"
  } else {
    $detail = "watchdog timeout ${TimeoutSec}s: $detail"
  }
}

$pass = $clicked
Write-Report $pass
Write-Host "CLICK_THROUGH status=$status clicked=$clicked rect=$rect attempts=$clickAttempts elapsed=${elapsedTotal}s"
exit $(if ($pass) { 0 } else { 1 })
