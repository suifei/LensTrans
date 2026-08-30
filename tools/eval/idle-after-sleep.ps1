# Short idle probe after sleep fix: 75s window, sample every 5s.
param(
  [int]$Seconds = 75,
  [int]$WarmupSec = 12,
  [int]$SampleIntervalSec = 5
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$TargetExe = Join-Path $Root "build\Release\lenstrans_e2e_target.exe"
$OverlayExe = Join-Path $Root "build\Release\lenstrans_overlay.exe"
$OutDir = Join-Path $Root "tools\eval\out"
$Md = Join-Path $OutDir "idle-after-sleep.md"
$Csv = Join-Path $OutDir "idle-after-sleep.csv"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path $TargetExe)) { throw "missing $TargetExe" }
if (-not (Test-Path $OverlayExe)) { throw "missing $OverlayExe" }

$stdoutPath = Join-Path $OutDir "e2e_target_idle_sleep.txt"
if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }

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
  $cores = [Environment]::ProcessorCount
  if ($cores -le 0) { $cores = 1 }
  return [math]::Round(($t2 - $t1).TotalSeconds / ($intervalSec * $cores) * 100, 3)
}

$target = $null
$overlay = $null
$rect = $null
$detail = ""
try {
  $target = Start-Process -FilePath $TargetExe -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath
  $deadline = [DateTime]::UtcNow.AddSeconds(8)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($target.HasExited) { break }
    $text = Get-Content $stdoutPath -Raw -ErrorAction SilentlyContinue
    if ($text -match 'E2E_TARGET rect=(\d+),(\d+),(\d+),(\d+)') {
      $rect = "$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4])"
      break
    }
    Start-Sleep -Milliseconds 150
  }
  if (-not $rect) { throw "e2e_target did not print rect within 8s" }

  Start-Sleep -Seconds 1
  $overlayLifeSec = $Seconds + 20
  $overlayArgs = @(
    "--e2e-wgc-window", "--e2e-sec", "$overlayLifeSec", "--e2e-stable", "--no-onboard",
    "--rect", $rect
  )
  $overlay = Start-Process -FilePath $OverlayExe -ArgumentList $overlayArgs -PassThru -WindowStyle Minimized
  $overlayStart = Get-Date
  Start-Sleep -Seconds 2

  $samples = New-Object System.Collections.Generic.List[string]
  $samples.Add("sec,cpu_pct,ws_mib,phase")
  $cpuAll = New-Object System.Collections.Generic.List[double]
  $cpuPostSleep = New-Object System.Collections.Generic.List[double]
  $sampleCount = [math]::Floor($Seconds / $SampleIntervalSec)

  for ($i = 0; $i -lt $sampleCount; $i++) {
    $elapsed = [int]((Get-Date) - $overlayStart).TotalSeconds
    if ($overlay.HasExited) {
      $detail = "overlay exited at t=${elapsed}s code=$($overlay.ExitCode)"
      break
    }
    $cpu = Measure-CpuPercent $overlay $SampleIntervalSec
    $overlay.Refresh()
    if ($overlay.HasExited) {
      $detail = "overlay exited during sample at t=${elapsed}s"
      break
    }
    $ws = [int64]$overlay.WorkingSet64
    $mib = [math]::Round($ws / 1MB, 1)
    $phase = if ($elapsed -lt $WarmupSec) { "bootstrap" } else { "post_sleep" }
    $cpuStr = if ($null -eq $cpu) { "" } else { "$cpu" }
    $samples.Add("$elapsed,$cpuStr,$mib,$phase")
    if ($null -ne $cpu) {
      $cpuAll.Add([double]$cpu)
      if ($phase -eq "post_sleep") { $cpuPostSleep.Add([double]$cpu) }
    }
    Write-Host "t=${elapsed}s CPU=$cpuStr% WS=$mib MiB phase=$phase"
  }

  if ($overlay -and -not $overlay.HasExited) {
    $overlay.WaitForExit(5000) | Out-Null
  }

  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllLines($Csv, $samples, $utf8)

  $avgAll = if ($cpuAll.Count) { [math]::Round(($cpuAll | Measure-Object -Average).Average, 3) } else { 0 }
  $avgPost = if ($cpuPostSleep.Count) { [math]::Round(($cpuPostSleep | Measure-Object -Average).Average, 3) } else { 0 }
  $maxPost = if ($cpuPostSleep.Count) { [math]::Round(($cpuPostSleep | Measure-Object -Maximum).Maximum, 3) } else { 0 }
  $completed = ($cpuAll.Count -ge $sampleCount) -and ($detail -eq "")
  $nearZero = ($avgPost -lt 0.5)

  $lines = @(
    "# Idle after sleep (Watching, static e2e_target)",
    "",
    "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "- status: $(if ($completed) { '**complete**' } else { '**incomplete**' })",
    "- command: ``$OverlayExe --e2e-wgc-window --e2e-sec $overlayLifeSec --e2e-stable --no-onboard --rect $rect``",
    "- sleep_policy: IdleWatch >=2s no DIFF -> WorkerLoop 400ms probe; DIFF wakes 70ms",
    "- warmup_s: $WarmupSec (exclude bootstrap OCR/stab/debounce from post-sleep avg)",
    "- duration_s: $Seconds (sample every ${SampleIntervalSec}s)",
    "- samples: $($cpuAll.Count) (post_sleep: $($cpuPostSleep.Count))",
    "",
    "## CPU",
    "",
    "- avg_cpu_pct_all: $avgAll",
    "- avg_cpu_pct_post_sleep: **$avgPost**",
    "- max_cpu_pct_post_sleep: $maxPost",
    "- idle_near_0pct: $(if ($nearZero) { '**yes** (post-sleep avg < 0.5%)' } else { '**no**' })",
    "",
    "## Verdict",
    "",
    "- stationary_idle_cpu: $(if (-not $completed) { '**incomplete**' } elseif ($nearZero) { '**pass**' } else { '**fail**' })",
    "- detail: $(if ($detail) { $detail } else { 'full sample window completed' })",
    "- goal_complete: **no**",
    "",
    "See ``idle-after-sleep.csv``."
  )
  [System.IO.File]::WriteAllLines($Md, $lines, $utf8)
  $lines | ForEach-Object { Write-Host $_ }

  if (-not $completed) { exit 2 }
  if (-not $nearZero) { exit 1 }
  exit 0
}
finally {
  Stop-All $overlay $target
}
