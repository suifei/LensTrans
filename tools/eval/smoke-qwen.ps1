# D3 smoke: load official Qwen2.5-0.5B Q4_K_M and run one en->zh prompt.
# Usage: powershell -File tools/eval/smoke-qwen.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path (Join-Path $root "CMakeLists.txt"))) {
    $root = "D:\works\LensTrans"
}
$cli = @(
    "$root\third_party\llama.cpp\build\bin\Release\llama-cli.exe",
    "$root\third_party\llama.cpp\build\Release\llama-cli.exe",
    "$root\third_party\llama.cpp\build\bin\llama-cli.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $cli) { throw "llama-cli.exe not found. Build b10688 first." }

$gguf = "$root\models\qwen2.5-0.5b-instruct-q4_k_m.gguf"
$hash = (Get-FileHash -Algorithm SHA256 $gguf).Hash
if ($hash -ne "74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB") {
    throw "GGUF SHA256 mismatch: $hash"
}

$outDir = "$root\tools\eval\out"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$promptFile = "$outDir\smoke-prompt.txt"
$promptText = "Translate the following segment into Chinese, without additional explanation.`r`n`r`nIt's on the house.`r`n"
[System.IO.File]::WriteAllText($promptFile, $promptText)
$log = "$outDir\smoke-qwen.log"
$errLog = "$outDir\smoke-qwen.err.log"
$memLog = "$outDir\smoke-qwen-mem.csv"

"ts_ms,working_set,private_bytes" | Set-Content -Encoding utf8 $memLog

$arg = @(
    "-m", $gguf,
    "-f", $promptFile,
    "-n", "64",
    "-c", "1024",
    "-b", "512",
    "-ngl", "0",
    "--temp", "0",
    "-t", "6",
    "--no-warmup",
    "--no-jinja",
    "--simple-io"
)

$p = Start-Process -FilePath $cli -ArgumentList $arg -PassThru -NoNewWindow `
    -RedirectStandardOutput $log -RedirectStandardError $errLog
$peakWs = 0L
$peakPriv = 0L
while (-not $p.HasExited) {
    try {
        $proc = Get-Process -Id $p.Id -ErrorAction Stop
        if ($proc.WorkingSet64 -gt $peakWs) { $peakWs = $proc.WorkingSet64 }
        if ($proc.PrivateMemorySize64 -gt $peakPriv) { $peakPriv = $proc.PrivateMemorySize64 }
        $now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        "$now,$($proc.WorkingSet64),$($proc.PrivateMemorySize64)" | Add-Content $memLog
    } catch { }
    Start-Sleep -Milliseconds 100
}
$p.WaitForExit()

Write-Output "exit=$($p.ExitCode)"
Write-Output "cli=$cli"
Write-Output "peak_ws_bytes=$peakWs"
Write-Output "peak_priv_bytes=$peakPriv"
Write-Output "log=$log"
