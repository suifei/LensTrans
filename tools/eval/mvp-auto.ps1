# Serial MVP auto checks. Do not fake green.
param(
  [switch]$SkipLlama,
  [int]$OverlayBudgetSec = 55
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OutDir = Join-Path $Root "tools\eval\out"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Report = Join-Path $OutDir "mvp-auto.md"
$Started = Get-Date
$Results = New-Object System.Collections.Generic.List[object]
$OverlaySec = 0.0

function Add-Result($id, $name, $pass, $evidence, $detail) {
  [void]$script:Results.Add([pscustomobject]@{ id=$id; name=$name; pass=$pass; evidence=$evidence; detail=$detail })
}

function Add-SkipResult($id, $name, $evidence, $detail) {
  Add-Result $id $name $null $evidence $detail
}

function Run-Cmd($id, $name, $file, $argList, $timeoutSec, [scriptblock]$PassIf) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  if ($argList -and $argList.Count -gt 0) {
    $p = Start-Process -FilePath $file -ArgumentList $argList -PassThru -NoNewWindow -WorkingDirectory $Root -Wait:$false
  } else {
    $p = Start-Process -FilePath $file -PassThru -NoNewWindow -WorkingDirectory $Root -Wait:$false
  }
  $ok = $p.WaitForExit($timeoutSec * 1000)
  if (-not $ok) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Add-Result $id $name $false "-" "timeout ${timeoutSec}s"
    return 1
  }
  $p.Refresh()
  $exitCode = $p.ExitCode
  if ($null -eq $exitCode) { $exitCode = 0 }
  $pass = & $PassIf $exitCode
  Add-Result $id $name $pass "$file exit=$exitCode" $(if ($pass) { "ok ${sw.ElapsedMilliseconds}ms" } else { "exit=$exitCode" })
  return $(if ($pass) { 0 } else { 1 })
}

function Invoke-EvalScript($id, $name, $scriptPath, $params, [switch]$IsOverlay) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $null = & $scriptPath @params 2>&1
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 0 }
  $elapsed = $sw.Elapsed.TotalSeconds
  if ($IsOverlay) { $script:OverlaySec += $elapsed }
  $pass = ($code -eq 0)
  Add-Result $id $name $pass $scriptPath $(if ($pass) { "ok ${elapsed}s" } else { "exit=$code ${elapsed}s" })
  return $(if ($pass) { 0 } else { 1 })
}

function Invoke-ClickThroughEval {
  $scriptPath = Join-Path $Root "tools\eval\click-through.ps1"
  $outMd = Join-Path $Root "tools\eval\out\click-through.md"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $null = & $scriptPath -TimeoutSec 15 2>&1
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 0 }
  $elapsed = $sw.Elapsed.TotalSeconds
  $script:OverlaySec += $elapsed

  $md = if (Test-Path $outMd) { Get-Content $outMd -Raw -Encoding UTF8 } else { "" }
  $clicked = ($md -match '(?m)^- saw_CLICKED:\s*yes\s*$')
  $hitTestReady = ($md -match '(?m)^- hit_test_ready:\s*yes\s*$')
  $sendInputUnits = 0
  if ($md -match '(?m)^- sendinput_units:\s*(\d+)\s*$') { $sendInputUnits = [int]$Matches[1] }

  if ($clicked) {
    Add-Result "click_through" "click-through 15s" $true $outMd "ok ${elapsed}s CLICKED"
    return 0
  }
  if (-not $hitTestReady) {
    Add-Result "click_through" "click-through 15s" $false $outMd "hit_test not ready exit=$code ${elapsed}s"
    return 1
  }
  if ($sendInputUnits -gt 0) {
    Add-Result "click_through" "click-through 15s" $false $outMd "SendInput $sendInputUnits units, no CLICKED ${elapsed}s"
    return 1
  }
  if ($sendInputUnits -eq 0) {
    Add-SkipResult "click_through" "click-through 15s" $outMd `
      "skip: SendInput blocked (0 units); hit_test=target — verify on interactive desktop"
    return 0
  }
  Add-Result "click_through" "click-through 15s" $false $outMd "exit=$code ${elapsed}s"
  return 1
}

$fail = 0
$testExe = Join-Path $Root "build\Release\lenstrans_test.exe"
if (-not (Test-Path $testExe)) { throw "missing $testExe" }
$fail += Run-Cmd "test_core" "lenstrans_test" $testExe @() 120 { param($c) $c -eq 0 }

$testHotkeyExe = Join-Path $Root "build\Release\lenstrans_test_hotkey.exe"
if (-not (Test-Path $testHotkeyExe)) { throw "missing $testHotkeyExe" }
$fail += Run-Cmd "test_hotkey" "lenstrans_test_hotkey" $testHotkeyExe @() 30 { param($c) $c -eq 0 }

$fail += Invoke-EvalScript "wgc_probe" "wgc-probe" (Join-Path $Root "tools\eval\wgc-probe.ps1") @{ TimeoutSec = 8 }

$fail += Invoke-EvalScript "overlay_e2e" "overlay-e2e stable 10s" (Join-Path $Root "tools\eval\overlay-e2e.ps1") @{
  Stable=$true; E2eSec=10; TimeoutSec=18 } -IsOverlay

$fail += Invoke-EvalScript "overlay_contrast" "overlay-contrast-e2e 10s" (Join-Path $Root "tools\eval\overlay-contrast-e2e.ps1") @{
  E2eSec=10; TimeoutSec=20 } -IsOverlay

$fail += Invoke-EvalScript "overlay_two_box" "overlay-two-box 12s" (Join-Path $Root "tools\eval\overlay-two-box.ps1") @{
  E2eSec=12; TimeoutSec=20 } -IsOverlay

$fail += Invoke-EvalScript "overlay_wgc_mon" "overlay-wgc-monitor 10s" (Join-Path $Root "tools\eval\overlay-wgc-monitor.ps1") @{
  E2eSec=10; TimeoutSec=18 } -IsOverlay

$fail += Invoke-ClickThroughEval

$fail += Invoke-EvalScript "hotkey_probe" "hotkey-probe 15s" (Join-Path $Root "tools\eval\hotkey-probe.ps1") @{
  TimeoutSec = 15 } -IsOverlay

$fail += Invoke-EvalScript "idle_wake" "idle-wake 25s" (Join-Path $Root "tools\eval\idle-wake.ps1") @{
  WatchdogSec = 25 }

Add-SkipResult "hotkey_ctrl_e" "hotkey-ctrl-e SendInput" "hotkey-ctrl-e.md" `
  "skip: RegisterHotKey ignores SendInput per Win32; use hotkey-probe.md"

if ($OverlaySec -gt $OverlayBudgetSec) {
  Add-Result "overlay_budget" "overlay budget" $false "${OverlaySec}s" "exceeded ${OverlayBudgetSec}s"
  $fail += 1
} else {
  Add-Result "overlay_budget" "overlay budget" $true "${OverlaySec}s" "within ${OverlayBudgetSec}s"
}

$packScript = Join-Path $Root "tools\pack\pack-windows.ps1"
$sizeMd = Join-Path $OutDir "installer-size.md"
$basePass = $false
$offPass = $null
try {
  & $packScript | Out-Null
  if (Test-Path $sizeMd) {
    $sm = Get-Content $sizeMd -Raw
    $basePass = ($sm -match "Limit 30 MB decimal:\s*\*\*PASS\*\*")
  }
  Add-Result "base_pack" "base pack 30MB" $basePass $sizeMd $(if ($basePass) { "PASS" } else { "FAIL" })
  if (-not $basePass) { $fail += 1 }
  $gguf = Join-Path $Root "models\qwen2.5-0.5b-instruct-q4_k_m.gguf"
  if (Test-Path $gguf) {
    & $packScript -Offline | Out-Null
    if (Test-Path $sizeMd) {
      $sm = Get-Content $sizeMd -Raw
      $offPass = ($sm -match "Limit 520 MB:\s*\*\*PASS\*\*")
    }
    Add-Result "offline_pack" "offline pack 520MB" $offPass $sizeMd $(if ($offPass) { "PASS" } else { "FAIL" })
    if (-not $offPass) { $fail += 1 }
  } else {
    Add-Result "offline_pack" "offline pack 520MB" $null $sizeMd "no gguf"
  }
} catch {
  Add-Result "base_pack" "base pack 30MB" $false $packScript $_.Exception.Message
  $fail += 1
}

$modelPath = Join-Path $Root "models\qwen2.5-0.5b-instruct-q4_k_m.gguf"
$llamaScript = Join-Path $Root "tools\eval\overlay-llama-e2e.ps1"
if (-not $SkipLlama -and (Test-Path $modelPath) -and (Test-Path $llamaScript)) {
  $fail += Invoke-EvalScript "overlay_llama" "overlay-llama optional" $llamaScript @{ E2eSec=35; TimeoutSec=45 }
} else {
  Add-Result "overlay_llama" "overlay-llama optional" $null "overlay-llama-e2e.md" "skipped"
}

$testPass = ($Results | Where-Object id -eq "test_core").pass
$wgcPass = ($Results | Where-Object id -eq "wgc_probe").pass
$e2ePass = ($Results | Where-Object id -eq "overlay_e2e").pass
$contrastPass = ($Results | Where-Object id -eq "overlay_contrast").pass
$twoBoxPass = ($Results | Where-Object id -eq "overlay_two_box").pass
$monPass = ($Results | Where-Object id -eq "overlay_wgc_mon").pass
$clickResult = $Results | Where-Object id -eq "click_through"
$clickPass = $clickResult.pass
$clickSkip = ($null -eq $clickPass)
function TransparentStatus([bool]$e2e, $click, [bool]$skip) {
  if ($e2e -and $click) { return "pass" }
  if ($e2e -and $skip) { return "partial" }
  return "fail"
}
$hotkeyPass = ($Results | Where-Object id -eq "hotkey_probe").pass
$llamaPass = ($Results | Where-Object id -eq "overlay_llama").pass
function S([bool]$p) { if ($p) { "pass" } else { "fail" } }
function SO($p) { if ($null -eq $p) { "partial" } elseif ($p) { "pass" } else { "fail" } }

$elapsed = ((Get-Date) - $Started).TotalSeconds
$allGreen = ($fail -eq 0)

$cn = Join-Path $PSScriptRoot "mvp-auto-checklist.cn.md"
$checklist = if (Test-Path $cn) { Get-Content $cn -Raw -Encoding UTF8 } else { "" }
if ($checklist) {
  $repl = @{
    "{{transparent}}" = TransparentStatus $e2ePass $clickPass $clickSkip
    "{{hotkey}}"      = SO $hotkeyPass
    "{{wgc}}"         = S ($wgcPass -and $monPass)
    "{{ocr}}"         = S $wgcPass
    "{{qwen}}"        = SO $llamaPass
    "{{cloud}}"       = S $testPass
    "{{present}}"     = S ($testPass -and $e2ePass)
    "{{multibox}}"    = S ($testPass -and $twoBoxPass)
    "{{cache}}"       = S $testPass
    "{{base}}"        = SO $basePass
    "{{offline}}"     = SO $offPass
  }
  foreach ($k in $repl.Keys) { $checklist = $checklist.Replace($k, $repl[$k]) }
}

$utf8 = New-Object System.Text.UTF8Encoding $false
$lines = @(
  "# MVP auto eval", "",
  "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "- duration_s: $([math]::Round($elapsed, 1))",
  "- overlay_elapsed_s: $([math]::Round($OverlaySec, 1))",
  "- overlay_budget_sec: $OverlayBudgetSec",
  "- script_all_green: $(if ($allGreen) { '**yes**' } else { '**no**' })",
  "- goal_complete: **no**", "",
  "## Run steps", "",
  "| step | pass | evidence | detail |",
  "| --- | --- | --- | --- |"
)
foreach ($r in $Results) {
  $p = if ($null -eq $r.pass) { "skip" } elseif ($r.pass) { "PASS" } else { "FAIL" }
  $lines += "| $($r.name) | $p | ``$($r.evidence)`` | $($r.detail) |"
}
$lines += ""
$lines += "## Goal checklist"
$lines += ""
if ($checklist) { $lines += $checklist.TrimEnd() } else {
  $lines += "| item | status | evidence |"
  $lines += "| transparent box | $(SO $e2ePass) | win/overlay/main.cpp |"
  $lines += "| WGC | $(S ($wgcPass -and $monPass)) | wgc-probe; overlay-wgc-monitor |"
  $lines += "| OCR | $(S $wgcPass) | mem_ok HELLO Settings |"
  $lines += "| local Qwen | $(SO $llamaPass) | quality-10; overlay-llama |"
  $lines += "| cloud mock SSE | $(S $testPass) | test_core |"
  $lines += "| tray/settings | partial | ui.cpp no HWND e2e |"
  $lines += "| immersive/sticker | $(S ($testPass -and $e2ePass)) | test_core; overlay-e2e |"
  $lines += "| multibox | $(S ($testPass -and $twoBoxPass)) | test_core; overlay-two-box |"
  $lines += "| cache/route | $(S $testPass) | test_core |"
  $lines += "| base 30MB | $(SO $basePass) | installer-size.md |"
  $lines += "| offline 520MB | $(SO $offPass) | installer-size.md |"
  $lines += "| WS 550MB | partial | quality-10 ~483 MiB |"
  $lines += "| macOS list | pass | mac/UNIMPLEMENTED.md |"
  $lines += "| W1 FLORES | fail | missing |"
  $lines += "| Mac device | fail | missing |"
  $lines += "| 8h soak | fail | missing |"
  $lines += "| signed MSIX | fail | missing |"
}
[System.IO.File]::WriteAllLines($Report, $lines, $utf8)
Write-Host "MVP_AUTO green=$allGreen fail=$fail overlay_s=$OverlaySec"
exit $(if ($allGreen) { 0 } else { 1 })