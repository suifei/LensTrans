# Ctrl+E hotkey e2e: overlay Watching -> SendInput Ctrl+E -> Editing (no WS_EX_TRANSPARENT) -> Ctrl+E -> Watching.
param(
  [int]$TimeoutSec = 15,
  [int]$E2eSec = 10
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OverlayExe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$Out = Join-Path $Root "tools\eval\out\hotkey-ctrl-e.md"
$OutDir = Split-Path $Out
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path $OverlayExe)) { throw "missing $OverlayExe — build lenstrans_overlay" }

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinHotkey {
  public const int GWL_EXSTYLE = -20;
  public const uint WS_EX_TRANSPARENT = 0x00000020;
  public const uint INPUT_KEYBOARD = 1;
  public const uint KEYEVENTF_KEYUP = 0x0002;
  public const ushort VK_CONTROL = 0x11;
  public const ushort VK_E = 0x45;
  public const uint WM_HOTKEY = 0x0312;
  public const int kHkEdit = 1;

  public delegate bool EnumProc(IntPtr h, IntPtr l);

  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion { [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
  }

  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lp, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] p, int cb);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);

  public static IntPtr OverlayHwnd = IntPtr.Zero;
  public static IntPtr HiddenHwnd = IntPtr.Zero;

  public static bool EnumAll(IntPtr h, IntPtr l) {
    var sb = new StringBuilder(256);
    GetClassName(h, sb, sb.Capacity);
    var cls = sb.ToString();
    if (cls == "LensTransOverlayPoC") OverlayHwnd = h;
    if (cls == "LensTransHidden") HiddenHwnd = h;
    return true;
  }

  public static void RefreshWindows() {
    OverlayHwnd = IntPtr.Zero;
    HiddenHwnd = IntPtr.Zero;
    EnumWindows(EnumAll, IntPtr.Zero);
  }

  public static bool IsClickThrough(IntPtr hwnd) {
    if (hwnd == IntPtr.Zero) return false;
    return (GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TRANSPARENT) != 0;
  }

  public static void SendCtrlE() {
    INPUT[] ins = new INPUT[4];
    ins[0].type = INPUT_KEYBOARD; ins[0].U.ki.wVk = VK_CONTROL;
    ins[1].type = INPUT_KEYBOARD; ins[1].U.ki.wVk = VK_E;
    ins[2].type = INPUT_KEYBOARD; ins[2].U.ki.wVk = VK_E; ins[2].U.ki.dwFlags = KEYEVENTF_KEYUP;
    ins[3].type = INPUT_KEYBOARD; ins[3].U.ki.wVk = VK_CONTROL; ins[3].U.ki.dwFlags = KEYEVENTF_KEYUP;
    SendInput(4, ins, Marshal.SizeOf(typeof(INPUT)));
  }

  public static void PostEditHotkey() {
    if (HiddenHwnd != IntPtr.Zero)
      PostMessage(HiddenHwnd, WM_HOTKEY, new IntPtr(kHkEdit), IntPtr.Zero);
  }
}
"@

$started = Get-Date
$overlay = $null
$watching0 = $false
$editing1 = $false
$watching2 = $false
$handlerToggle = $false
$detail = ""
$status = "fail"

function Write-Report($pass) {
  $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# Hotkey Ctrl+E (edit / click-through toggle)",
    "",
    "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "- status: $(if ($pass) { '**pass**' } else { '**fail**' })",
    "- hotkey_ctrl_e: $(if ($pass) { '**yes**' } else { '**no**' })",
    "- initial_watching_transparent: $(if ($watching0) { 'yes' } else { 'no' })",
    "- after_first_ctrl_e_editing: $(if ($editing1) { 'yes' } else { 'no' })",
    "- after_second_ctrl_e_watching: $(if (-not $editing1) { 'n/a' } elseif ($watching2) { 'yes' } else { 'no' })",
    "- wm_hotkey_handler_probe: $(if ($handlerToggle) { 'yes (PostMessage WM_HOTKEY toggles exstyle)' } else { 'no' })",
    "- overlay_mode: Watching (--e2e-sec $E2eSec --e2e-stable --no-onboard)",
    "- assert: SendInput Ctrl+E -> GWL_EXSTYLE WS_EX_TRANSPARENT off then on",
    "- elapsed_s: $elapsed",
    "- detail: $detail",
    "- goal_complete: **no**"
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
}

function Wait-Overlay([int]$ms) {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($ms)
  while ([DateTime]::UtcNow -lt $deadline) {
    [WinHotkey]::RefreshWindows()
    if ([WinHotkey]::OverlayHwnd -ne [IntPtr]::Zero) { return $true }
    Start-Sleep -Milliseconds 100
  }
  return $false
}

function Wait-ExStyle([IntPtr]$hwnd, [scriptblock]$Predicate, [int]$ms) {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($ms)
  while ([DateTime]::UtcNow -lt $deadline) {
    [WinHotkey]::RefreshWindows()
    if ($hwnd -eq [IntPtr]::Zero) { $hwnd = [WinHotkey]::OverlayHwnd }
    if ($hwnd -ne [IntPtr]::Zero -and (& $Predicate $hwnd)) { return $true }
    Start-Sleep -Milliseconds 80
  }
  return $false
}

try {
  $overlayArgs = @("--e2e-sec", "$E2eSec", "--e2e-stable", "--no-onboard")
  $overlay = Start-Process -FilePath $OverlayExe -ArgumentList $overlayArgs -PassThru -NoNewWindow -Wait:$false

  if (-not (Wait-Overlay 8000)) {
    $detail = "overlay LensTransOverlayPoC not found within 8s"
    Write-Report $false
    Write-Host "HOTKEY_CTRL_E status=fail reason=no_hwnd"
    exit 2
  }

  Start-Sleep -Milliseconds 500
  [WinHotkey]::RefreshWindows()
  $hwnd = [WinHotkey]::OverlayHwnd
  $watching0 = [WinHotkey]::IsClickThrough($hwnd)

  if (-not $watching0) {
    $detail = "initial state not Watching (WS_EX_TRANSPARENT missing on overlay)"
    Write-Report $false
    Write-Host "HOTKEY_CTRL_E status=fail reason=not_watching"
    exit 3
  }

  [WinHotkey]::SendCtrlE()
  $editing1 = Wait-ExStyle $hwnd { param($h) -not [WinHotkey]::IsClickThrough($h) } 2000

  Start-Sleep -Milliseconds 150
  [WinHotkey]::SendCtrlE()
  if ($editing1) {
    $watching2 = Wait-ExStyle $hwnd { param($h) [WinHotkey]::IsClickThrough($h) } 2000
  }

  if ($editing1 -and $watching2) {
    $status = "pass"
    $detail = "SendInput Ctrl+E x2; WS_EX_TRANSPARENT off then on"
  } elseif (-not $editing1) {
    # Handler probe: Windows API docs say SendInput does not trigger RegisterHotKey.
    [WinHotkey]::RefreshWindows()
    $before = [WinHotkey]::IsClickThrough([WinHotkey]::OverlayHwnd)
    [WinHotkey]::PostEditHotkey()
    Start-Sleep -Milliseconds 400
    [WinHotkey]::RefreshWindows()
    $after = [WinHotkey]::IsClickThrough([WinHotkey]::OverlayHwnd)
    $handlerToggle = ($before -and -not $after)
    $detail = "SendInput Ctrl+E did not toggle (RegisterHotKey ignores injected input per Win32); handler_probe=$handlerToggle"
  } else {
    $detail = "second SendInput Ctrl+E did not restore WS_EX_TRANSPARENT"
  }
} catch {
  $detail = $_.Exception.Message
} finally {
  if ($overlay -and -not $overlay.HasExited) {
    Stop-Process -Id $overlay.Id -Force -ErrorAction SilentlyContinue
  }
}

$elapsedTotal = ((Get-Date) - $started).TotalSeconds
if ($elapsedTotal -gt $TimeoutSec -and $status -ne "pass") {
  $detail = "watchdog ${TimeoutSec}s; $detail"
}

$pass = ($status -eq "pass")
Write-Report $pass
Write-Host "HOTKEY_CTRL_E status=$status watching0=$watching0 editing1=$editing1 watching2=$watching2 handler=$handlerToggle elapsed=${elapsedTotal}s"
exit $(if ($pass) { 0 } else { 1 })
