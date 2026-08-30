# Run the WGC probe with a hard timeout. Do not wait on a permission dialog.
param([int]$TimeoutSec = 8)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Exe = Join-Path $Root "build\Release\lenstrans_wgc_probe.exe"
$Out = Join-Path $Root "tools\eval\out\wgc-probe.md"
if (-not (Test-Path $Exe)) { throw "missing $Exe — build lenstrans_wgc_probe" }
$p = Start-Process -FilePath $Exe -PassThru -NoNewWindow -Wait:$false
$ok = $p.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# WGC probe (not a full overlay acceptance)",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- elapsed_ms: $($TimeoutSec * 1000)",
    "- detail: process killed after ${TimeoutSec}s (likely a permission dialog or hang)",
    "- ocr: not run",
    "- note: do not treat as authorized. User may need to allow screen recording."
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "WGC_PROBE status=timeout"
  exit 3
}
Write-Host "WGC_PROBE exit=$($p.ExitCode)"
exit $p.ExitCode
