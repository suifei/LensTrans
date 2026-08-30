# Short working-set sample. NOT an 8h soak / NOT a leak-free verdict.
param(
  [int]$Seconds = 90,
  [string]$Exe = ""
)

$ErrorActionPreference = "Stop"
if ($Seconds -lt 60 -or $Seconds -gt 120) {
  throw "Seconds must be 60–120 (this is a short probe, not 8h)"
}
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Exe) { $Exe = Join-Path $Root "build\Release\lenstrans_overlay.exe" }
if (-not (Test-Path $Exe)) { throw "missing $Exe" }

$outDir = Join-Path $Root "tools\eval\out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$csv = Join-Path $outDir "ws-probe.csv"
$md = Join-Path $outDir "ws-probe.md"

$p = Start-Process -FilePath $Exe -ArgumentList @("--ws-probe", "$Seconds") -PassThru -WindowStyle Minimized
$samples = New-Object System.Collections.Generic.List[string]
$samples.Add("sec,ws_bytes,ws_mib")
$t0 = Get-Date
try {
  while (-not $p.HasExited) {
    $elapsed = [int]((Get-Date) - $t0).TotalSeconds
    $p.Refresh()
    if ($p.HasExited) { break }
    $ws = [int64]$p.WorkingSet64
    $mib = "{0:N1}" -f ($ws / 1MB)
    $samples.Add("$elapsed,$ws,$mib")
    Write-Host "t=${elapsed}s WS=$mib MiB"
    if ($elapsed -ge ($Seconds + 15)) {
      Write-Host "watchdog: killing probe process"
      Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      break
    }
    Start-Sleep -Seconds 5
  }
} finally {
  if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  }
}

$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($csv, $samples, $utf8)

$nums = @()
foreach ($line in $samples) {
  if ($line -match "^[0-9]") {
    $parts = $line.Split(",")
    $nums += [int64]$parts[1]
  }
}
$min = if ($nums.Count) { ($nums | Measure-Object -Minimum).Minimum } else { 0 }
$max = if ($nums.Count) { ($nums | Measure-Object -Maximum).Maximum } else { 0 }
$first = if ($nums.Count) { $nums[0] } else { 0 }
$last = if ($nums.Count) { $nums[-1] } else { 0 }
$delta = $last - $first

$lines = @(
  "# WS probe (NOT 8h soak)",
  "",
  "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "- exe: ``$Exe --ws-probe $Seconds``",
  "- duration_s: $Seconds (range 60-120 only)",
  "- samples: $($nums.Count)",
  "- first_ws_mib: $([math]::Round($first/1MB,1))",
  "- last_ws_mib: $([math]::Round($last/1MB,1))",
  "- min_ws_mib: $([math]::Round($min/1MB,1))",
  "- max_ws_mib: $([math]::Round($max/1MB,1))",
  "- delta_last_minus_first_mib: $([math]::Round($delta/1MB,1))",
  "- model loaded: no (probe skips engines and capture; no screen-permission dialog)",
  "- verdict: **not an 8h acceptance**. Only a short WS sample. Do not treat a flat 90s line as leak-free.",
  "",
  "See ``ws-probe.csv``."
)
[System.IO.File]::WriteAllLines($md, $lines, $utf8)
$lines | ForEach-Object { Write-Host $_ }
