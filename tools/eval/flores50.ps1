# FLORES-200 dev first-50 greedy EN-ZH (not formal W1, no COMET).
param([int]$TimeoutSec = 180)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OutDir = Join-Path $Root "tools\eval\out"
$Exe = Join-Path $Root "build\Release\lenstrans_test_llama.exe"
$Out = Join-Path $OutDir "flores50.md"
$Tgz = Join-Path $OutDir "flores200_dataset.tar.gz"
$EnOut = Join-Path $OutDir "flores50-en.txt"
$RefOut = Join-Path $OutDir "flores50-ref.txt"
$utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Skip([string]$Reason) {
  $lines = @(
    "# flores50 greedy EN-ZH (FLORES-200 dev sample, not formal W1, no COMET)",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **skip**",
    "- reason: $Reason",
    "- note: not W1 acceptance; no COMET/BLEU."
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "FLORES50 status=skip reason=$Reason"
  exit 2
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$srcEn = Join-Path $OutDir "flores200_dataset\dev\eng_Latn.dev"
$srcZh = Join-Path $OutDir "flores200_dataset\dev\zho_Hans.dev"
if (-not (Test-Path $srcEn) -or -not (Test-Path $srcZh)) {
  if (-not (Test-Path $Tgz)) {
    try {
      curl.exe -L --connect-timeout 30 --max-time 240 -o $Tgz "https://dl.fbaipublicfiles.com/nllb/flores200_dataset.tar.gz" | Out-Null
    } catch {
      Write-Skip "download failed: $($_.Exception.Message)"
    }
    if (-not (Test-Path $Tgz) -or (Get-Item $Tgz).Length -lt 1000000) {
      Write-Skip "tarball missing or too small after download"
    }
  }
  tar -xf $Tgz -C $OutDir flores200_dataset/dev/eng_Latn.dev flores200_dataset/dev/zho_Hans.dev 2>$null
}
if (-not (Test-Path $srcEn) -or -not (Test-Path $srcZh)) {
  Write-Skip "FLORES-200 dev files not found after extract"
}
$en = Get-Content $srcEn -Encoding UTF8 -TotalCount 50
$zh = Get-Content $srcZh -Encoding UTF8 -TotalCount 50
if ($en.Count -lt 1 -or $zh.Count -lt 1) {
  Write-Skip "empty eng_Latn or zho_Hans dev split"
}
[System.IO.File]::WriteAllLines($EnOut, $en, $utf8)
[System.IO.File]::WriteAllLines($RefOut, $zh, $utf8)

if (-not (Test-Path $Exe)) { Write-Skip "missing $Exe" }
$p = Start-Process -FilePath $Exe -ArgumentList @("--flores50") -PassThru -NoNewWindow -Wait:$false
$ok = $p.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  $lines = @(
    "# flores50 greedy EN-ZH (FLORES-200 dev sample, not formal W1, no COMET)",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- elapsed_ms: $($TimeoutSec * 1000)",
    "- sentences_requested: $($en.Count)",
    "- detail: process killed after ${TimeoutSec}s",
    "- note: partial or missing rows; not W1 acceptance."
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "FLORES50 status=timeout"
  exit 3
}
Write-Host "FLORES50 exit=$($p.ExitCode)"
exit $p.ExitCode
