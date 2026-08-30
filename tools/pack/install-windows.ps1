# Copy the staged base pack to %LOCALAPPDATA%\LensTrans\app. No GGUF, no secrets.
param(
  [string]$From = "",
  [switch]$StartMenu
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $From) { $From = Join-Path $Root "dist\windows-base" }
if (-not (Test-Path (Join-Path $From "lenstrans_overlay.exe"))) {
  throw "run tools/pack/pack-windows.ps1 first ($From missing exe)"
}
$gguf = Get-ChildItem $From -Filter *.gguf -ErrorAction SilentlyContinue
if ($gguf) { throw "refusing to install a tree that contains GGUF" }

$dest = Join-Path $env:LOCALAPPDATA "LensTrans\app"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $From "*") $dest -Force
Write-Host "installed to $dest"

if ($StartMenu) {
  $lnkDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
  New-Item -ItemType Directory -Force -Path $lnkDir | Out-Null
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut((Join-Path $lnkDir "LensTrans.lnk"))
  $lnk.TargetPath = Join-Path $dest "lenstrans_overlay.exe"
  $lnk.WorkingDirectory = $dest
  $lnk.Save()
  Write-Host "Start Menu shortcut written"
}
