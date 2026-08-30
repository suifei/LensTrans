# Idle 5min: overlay Watching over static e2e_target (fake engine, no llama).
# Sample CPU + WS every 5s for 300s; watchdog 360s.
param(
  [int]$Seconds = 300,
  [int]$WatchdogSec = 360,
  [int]$SampleIntervalSec = 5
)

$ErrorActionPreference = "Stop"
if ($Seconds -lt 60) { throw "Seconds must be >= 60" }
if ($WatchdogSec -lt $Seconds) { throw "WatchdogSec must be >= Seconds" }

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TargetExe = Join-Path $Root "build\Release\lenstrans_e2e_target.exe"
$OverlayExe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$OutDir = Join-Path $Root "tools\eval\out"
$Md = Join-Path $OutDir "idle-5min.md"
$Csv = Join-Path $OutDir "idle-5min.csv"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path $TargetExe)) { throw "missing $TargetExe" }
if (-not (Test-Path $OverlayExe)) { throw "missing $OverlayExe" }

$stdoutPath = Join-Path $OutDir "e2e_target_idle.txt"
if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }

$target = $null
$overlay = $null
$rect = $null
$rx = 0; $ry = 0; $rw = 0; $rh = 0
$status = "fail"
$detail = ""

function Read-TargetStdout {
  if (-not (Test-Path $stdoutPath)) { return $null }
  return Get-Content $stdoutPath -Raw -ErrorAction SilentlyContinue
}

function Stop-All {
  param([System.Diagnostics.Process]$ov, [System.Diagnostics.Process]$tg)
  foreach ($p in @($ov, $tg)) {
    if ($p -and -not $p.HasExited) {
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
  }
}

function Measure-CpuPercent([System.Diagnostics.Process]$proc, [double]$intervalSec) {
  $proc.Refresh()
  if ($proc.HasExited) { return $null }
  $t1 = $proc.TotalProcessorTime
  Start-Sleep -Seconds $intervalSec
  $proc.Refresh()
  if ($proc.HasExited) { return $null }
  $t2 = $proc.TotalProcessorTime
  $delta = ($t2 - $t1).TotalSeconds
  $cores = [Environment]::ProcessorCount
  if ($cores -le 0) { $cores = 1 }
  return [math]::Round(($delta / ($intervalSec * $cores)) * 100, 3)
}

try {
  $target = Start-Process -FilePath $TargetExe -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath
  $deadline = [DateTime]::UtcNow.AddSeconds(8)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($target.HasExited) { break }
    $text = Read-TargetStdout
    if ($text -match 'E2E_TARGET rect=(\d+),(\d+),(\d+),(\d+)') {
      $rx = [int]$Matches[1]; $ry = [int]$Matches[2]; $rw = [int]$Matches[3]; $rh = [int]$Matches[4]
      $rect = "$rx,$ry,$rw,$rh"
      break
    }
    Start-Sleep -Milliseconds 150
  }
  if (-not $rect) {
    $detail = "e2e_target did not print rect within 8s"
    throw $detail
  }

  Start-Sleep -Seconds 1
  # e2e-sec keeps overlay alive through full sample window (+15s margin for bootstrap).
  $overlayLifeSec = $Seconds + 15
  $overlayArgs = @(
    "--e2e-wgc-window", "--e2e-sec", "$overlayLifeSec", "--e2e-stable", "--no-onboard",
    "--rect", $rect
  )
  $overlay = Start-Process -FilePath $OverlayExe -ArgumentList $overlayArgs -PassThru -WindowStyle Minimized
  $overlayStart = Get-Date
  Start-Sleep -Seconds 2

  if ($overlay.HasExited) {
    $detail = "overlay exited early code=$($overlay.ExitCode)"
    throw $detail
  }

  $samples = New-Object System.Collections.Generic.List[string]
  $samples.Add("sec,cpu_pct,ws_bytes,ws_mib")
  $cpuVals = New-Object System.Collections.Generic.List[double]
  $wsVals = New-Object System.Collections.Generic.List[int64]
  $sampleCount = [math]::Floor($Seconds / $SampleIntervalSec)

  for ($i = 0; $i -lt $sampleCount; $i++) {
    $elapsed = [int]((Get-Date) - $overlayStart).TotalSeconds
    if ($elapsed -ge $WatchdogSec) {
      $detail = "watchdog ${WatchdogSec}s reached at sample $i"
      break
    }
    if ($overlay.HasExited) {
      $detail = "overlay exited at t=${elapsed}s code=$($overlay.ExitCode)"
      break
    }

    $cpu = Measure-CpuPercent $overlay $SampleIntervalSec
    $overlay.Refresh()
    if ($overlay.HasExited) {
      $detail = "overlay exited during CPU sample at t=${elapsed}s"
      break
    }
    $ws = [int64]$overlay.WorkingSet64
    $mib = "{0:N1}" -f ($ws / 1MB)
    $cpuStr = if ($null -eq $cpu) { "" } else { "$cpu" }
    $samples.Add("$elapsed,$cpuStr,$ws,$mib")
    if ($null -ne $cpu) { $cpuVals.Add([double]$cpu) }
    $wsVals.Add($ws)
    Write-Host "t=${elapsed}s CPU=$cpuStr% WS=$mib MiB"
  }

  if ($overlay -and -not $overlay.HasExited) {
    $overlay.WaitForExit(15000) | Out-Null
  }

  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($Csv, $samples, $utf8)

  $avgCpu = if ($cpuVals.Count) { [math]::Round(($cpuVals | Measure-Object -Average).Average, 3) } else { 0 }
  $maxCpu = if ($cpuVals.Count) { [math]::Round(($cpuVals | Measure-Object -Maximum).Maximum, 3) } else { 0 }
  $minWs = if ($wsVals.Count) { ($wsVals | Measure-Object -Minimum).Minimum } else { 0 }
  $maxWs = if ($wsVals.Count) { ($wsVals | Measure-Object -Maximum).Maximum } else { 0 }
  $avgWs = if ($wsVals.Count) { ($wsVals | Measure-Object -Average).Average } else { 0 }
  $firstWs = if ($wsVals.Count) { $wsVals[0] } else { 0 }
  $lastWs = if ($wsVals.Count) { $wsVals[-1] } else { 0 }

  $idleThreshold = 1.0
  $cpuNearZero = ($avgCpu -lt $idleThreshold)
  $wsUnder550 = ($maxWs / 1MB) -le 550
  $completed = ($cpuVals.Count -ge $sampleCount) -and ($detail -eq "")
  $status = if ($completed) { "complete" } else { "incomplete" }

  $stationaryVerdict = if (-not $completed) { '**fail or incomplete**' }
    elseif ($cpuNearZero) { '**pass** (avg CPU near 0%)' }
    else { '**fail** (avg CPU not near 0%)' }

  $lines = @(
    "# Idle 5min (Watching, static e2e_target, no llama)",
    "",
    "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "- status: **$status**",
    "- command: ``$OverlayExe --e2e-wgc-window --e2e-sec $overlayLifeSec --e2e-stable --no-onboard --rect $rect``",
    "- idle_window_s: $Seconds (sample every ${SampleIntervalSec}s from overlay start)",
    "- target: ``$TargetExe`` rect=$rect (static HELLO Settings)",
    "- duration_s: $Seconds (sample every ${SampleIntervalSec}s, watchdog ${WatchdogSec}s)",
    "- samples: $($cpuVals.Count)",
    "- model loaded: **no** (fake engine only; no --e2e-llama)",
    "",
    "## CPU",
    "",
    "- avg_cpu_pct: $avgCpu",
    "- max_cpu_pct: $maxCpu",
    "- idle_near_0pct: $(if ($cpuNearZero) { '**yes** (avg < 1%)' } else { '**no** (avg >= 1%)' })",
    "",
    "## Working Set",
    "",
    "- first_ws_mib: $([math]::Round($firstWs/1MB,1))",
    "- last_ws_mib: $([math]::Round($lastWs/1MB,1))",
    "- avg_ws_mib: $([math]::Round($avgWs/1MB,1))",
    "- min_ws_mib: $([math]::Round($minWs/1MB,1))",
    "- max_ws_mib: $([math]::Round($maxWs/1MB,1))",
    "- ws_under_550mb: $(if ($wsUnder550) { '**yes**' } else { '**no**' })",
    "",
    "## Verdict",
    "",
    "- stationary_5min_cpu_0pct: $stationaryVerdict",
    "- detail: $(if ($detail) { $detail } else { 'full sample window completed' })",
    "- goal_complete: **no**",
    "",
    "See ``idle-5min.csv``."
  )
  [System.IO.File]::WriteAllLines($Md, $lines, $utf8)
  $lines | ForEach-Object { Write-Host $_ }

  if (-not $completed) { exit 2 }
  if (-not $cpuNearZero) { exit 1 }
  exit 0
}
finally {
  Stop-All $overlay $target
}
