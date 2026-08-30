# Run quality-30 greedy eval with a hard timeout (not 8h).
param([int]$TimeoutSec = 120)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Exe = Join-Path $Root "build\Release\lenstrans_test_llama.exe"
$Out = Join-Path $Root "tools\eval\out\quality-30.md"
if (-not (Test-Path $Exe)) { throw "missing $Exe — build lenstrans_test_llama" }
$p = Start-Process -FilePath $Exe -ArgumentList @("--quality-30") -PassThru -NoNewWindow -Wait:$false
$ok = $p.WaitForExit($TimeoutSec * 1000)
if (-not $ok) {
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $lines = @(
    "# quality-30 greedy EN-ZH (not FLORES, not W1)",
    "",
    "- date: $(Get-Date -Format yyyy-MM-dd)",
    "- status: **timeout**",
    "- elapsed_ms: $($TimeoutSec * 1000)",
    "- detail: process killed after ${TimeoutSec}s",
    "- note: partial or missing rows; not W1 acceptance."
  )
  [System.IO.File]::WriteAllLines($Out, $lines, $utf8)
  Write-Host "QUALITY30 status=timeout"
  exit 3
}
Write-Host "QUALITY30 exit=$($p.ExitCode)"
exit $p.ExitCode
