# Pack LensTrans Windows base (no GGUF) or offline (base + models/*.gguf).
param(
  [switch]$Offline,
  [string]$BuildDir = "",
  [string]$OutRoot = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $BuildDir) { $BuildDir = Join-Path $Root "build\Release" }
if (-not $OutRoot) { $OutRoot = Join-Path $Root "dist" }

$BaseDir = Join-Path $OutRoot "windows-base"
$OffDir = Join-Path $OutRoot "windows-offline"
$Report = Join-Path $Root "tools\eval\out\installer-size.md"

$Need = @(
  "lenstrans_overlay.exe",
  "llama.dll",
  "ggml.dll",
  "ggml-base.dll",
  "ggml-cpu.dll"
)

$overlayPath = Join-Path $BuildDir "lenstrans_overlay.exe"
if (-not (Test-Path $overlayPath)) {
  # Ninja writes single-config targets at the build root; some generators place
  # the same target under a Release subdirectory. Normalize both layouts here.
  $releaseDir = Join-Path $BuildDir "Release"
  if (Test-Path (Join-Path $releaseDir "lenstrans_overlay.exe")) {
    $BuildDir = $releaseDir
    $overlayPath = Join-Path $BuildDir "lenstrans_overlay.exe"
  } else {
    throw "missing overlay in $BuildDir or $releaseDir — build Release first"
  }
}

New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null
Get-ChildItem $BaseDir -Force | Remove-Item -Recurse -Force
New-Item -ItemType Directory -Force -Path $BaseDir | Out-Null

$files = @()
foreach ($n in $Need) {
  $src = Join-Path $BuildDir $n
  if (-not (Test-Path $src)) { throw "missing $src" }
  Copy-Item $src (Join-Path $BaseDir $n) -Force
  $files += Get-Item (Join-Path $BaseDir $n)
}

# Refuse to copy any GGUF into the base tree.
Get-ChildItem $BaseDir -Recurse -Filter *.gguf -ErrorAction SilentlyContinue | ForEach-Object {
  throw "GGUF leaked into base pack: $($_.FullName)"
}

$baseBytes = ($files | Measure-Object -Property Length -Sum).Sum
$zip = Join-Path $OutRoot "LensTrans-windows-base.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $BaseDir "*") -DestinationPath $zip -Force
$zipBytes = (Get-Item $zip).Length

$limitBase = 30L * 1000L * 1000L
$limitOff = 520L * 1000L * 1000L
$baseOk = $baseBytes -le $limitBase
$zipOk = $zipBytes -le $limitBase

$offBytes = 0L
$offOk = $true
$ggufName = ""
$ggufBytes = 0L
if ($Offline) {
  New-Item -ItemType Directory -Force -Path $OffDir | Out-Null
  Get-ChildItem $OffDir -Force | Remove-Item -Recurse -Force
  New-Item -ItemType Directory -Force -Path $OffDir | Out-Null
  Copy-Item (Join-Path $BaseDir "*") $OffDir -Force
  $gguf = Get-ChildItem (Join-Path $Root "models") -Filter *.gguf -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "qwen2.5-0.5b-instruct-q4_k_m.gguf" } |
    Select-Object -First 1
  if (-not $gguf) {
    $gguf = Get-ChildItem (Join-Path $Root "models") -Filter *.gguf -ErrorAction SilentlyContinue |
      Select-Object -First 1
  }
  if (-not $gguf) { throw "offline pack requested but models/*.gguf missing" }
  $ggufName = $gguf.Name
  $ggufBytes = $gguf.Length
  Copy-Item $gguf.FullName (Join-Path $OffDir $gguf.Name) -Force
  $offBytes = (Get-ChildItem $OffDir -File | Measure-Object -Property Length -Sum).Sum
  $offOk = $offBytes -le $limitOff
}

function Mb([int64]$b) { "{0:N2}" -f ($b / 1MB) }
function DecMb([int64]$b) { "{0:N2}" -f ($b / 1000000.0) }

$lines = @(
  "# installer size (not MSIX; script pack)",
  "",
  "- date: $(Get-Date -Format yyyy-MM-dd)",
  "- host: Windows x64, self-written pack (no Inno/NSIS/Electron)",
  "- base dir: ``dist/windows-base/``",
  "- zip: ``dist/LensTrans-windows-base.zip``",
  "- GGUF in base: no",
  "",
  "| file | bytes |",
  "| --- | ---: |"
)
foreach ($f in $files) {
  $lines += "| $($f.Name) | $($f.Length) |"
}
$lines += "| **base sum** | **$baseBytes** |"
$lines += "| zip | $zipBytes |"
$lines += ""
$lines += "- base sum: $(DecMb $baseBytes) MB (decimal) / $(Mb $baseBytes) MiB. Limit 30 MB decimal: **$(if ($baseOk) { 'PASS' } else { 'FAIL' })**"
$lines += "- zip: $(DecMb $zipBytes) MB decimal: **$(if ($zipOk) { 'PASS' } else { 'FAIL' })**"
$lines += "- VC++ runtime / Universal CRT: not bundled (system)."
if ($Offline) {
  $lines += "- offline dir: ``dist/windows-offline/``"
  $lines += "- gguf: $ggufName ($ggufBytes bytes)"
  $lines += "- offline sum: $offBytes bytes ($(DecMb $offBytes) MB decimal). Limit 520 MB: **$(if ($offOk) { 'PASS' } else { 'FAIL' })**"
} else {
  $lines += "- offline: not packed this run (``-Offline`` to add models/*.gguf)."
}
$lines += ""
$lines += "This is a directory + zip. Not a signed MSIX. Install: ``tools/pack/install-windows.ps1``."

New-Item -ItemType Directory -Force -Path (Split-Path $Report) | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($Report, $lines, $utf8)
$lines | ForEach-Object { Write-Host $_ }

if (-not $baseOk) { throw "base pack $baseBytes exceeds 30e6" }
if ($Offline -and -not $offOk) { throw "offline pack $offBytes exceeds 520e6" }
