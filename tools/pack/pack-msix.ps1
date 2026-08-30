# Pack dist/windows-base (exe + llama DLLs, no GGUF) into an MSIX; optional -TestSign (self-signed, not production).
param(
  [string]$BaseDir = "",
  [string]$OutMsix = "",
  [string]$MakeAppx = "",
  [switch]$TestSign
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ManifestSrc = Join-Path $PSScriptRoot "msix\AppxManifest.xml"
$Report = Join-Path $Root "tools\eval\out\installer-size.md"
$KitsBin = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"

if (-not $BaseDir) { $BaseDir = Join-Path $Root "dist\windows-base" }
if (-not $OutMsix) { $OutMsix = Join-Path $Root "dist\LensTrans-windows-base.msix" }

function Resolve-MakeAppx {
  param([string]$Override)
  if ($Override -and (Test-Path $Override)) { return (Resolve-Path $Override).Path }
  if (-not (Test-Path $KitsBin)) { return $null }
  $found = @(Get-ChildItem -Path $KitsBin -Recurse -Filter "makeappx.exe" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
  if ($found.Count -eq 0) { return $null }
  $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
  $pick = @($found | Where-Object { $_ -match [regex]::Escape("\$arch\makeappx.exe") })[0]
  if (-not $pick) { $pick = $found[0] }
  return $pick
}

function Write-MinimalPng([string]$Path) {
  $b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  $bytes = [Convert]::FromBase64String($b64)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllBytes($Path, $bytes)
}

function Format-DecMb([int64]$b) { return ("{0:N2}" -f ($b / 1000000.0)) }

function Resolve-SignTool {
  param([string]$MakeAppxPath)
  if ($MakeAppxPath) {
    $sameDir = Join-Path (Split-Path $MakeAppxPath -Parent) "signtool.exe"
    if (Test-Path $sameDir) { return (Resolve-Path $sameDir).Path }
  }
  $preferred = Join-Path $KitsBin "10.0.26100.0\x64\signtool.exe"
  if (Test-Path $preferred) { return (Resolve-Path $preferred).Path }
  if (-not (Test-Path $KitsBin)) { return $null }
  $found = @(Get-ChildItem -Path $KitsBin -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
  if ($found.Count -eq 0) { return $null }
  $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
  $pick = @($found | Where-Object { $_ -match [regex]::Escape("\$arch\signtool.exe") })[0]
  if (-not $pick) { $pick = $found[0] }
  return $pick
}

function Invoke-TestSignMsix {
  param(
    [string]$MsixPath,
    [string]$SignToolPath,
    [string]$PfxPath
  )
  $pfxDir = Split-Path -Parent $PfxPath
  if (-not (Test-Path $pfxDir)) { New-Item -ItemType Directory -Force -Path $pfxDir | Out-Null }

  $plainPassword = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
  $securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

  $cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=LensTrans-Dev-Unsigned" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(1)

  try {
    Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $securePassword | Out-Null
    & $SignToolPath sign /fd SHA256 /a /f $PfxPath /p $plainPassword $MsixPath
    if ($LASTEXITCODE -ne 0) { throw "signtool sign failed exit $LASTEXITCODE" }
  } finally {
    $plainPassword = $null
    Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
  }

  return @{
    Subject = $cert.Subject
    PfxPath = $PfxPath
  }
}

$makeappxPath = Resolve-MakeAppx -Override $MakeAppx
$signToolPath = Resolve-SignTool -MakeAppxPath $makeappxPath
$pfxPath = Join-Path $Root "dist\test-code-sign.pfx"
$signed = $false
$signMode = "unsigned"
$signVerify = "n/a"
$signToolNote = ""
$searched = ""
if (Test-Path $KitsBin) {
  $searched = (Get-ChildItem -Path $KitsBin -Recurse -Filter "makeappx.exe" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName) -join "; "
} else {
  $searched = "Kits bin root missing: $KitsBin"
}

if (-not (Test-Path $ManifestSrc)) { throw "missing manifest: $ManifestSrc" }
if (-not (Test-Path $BaseDir)) { throw "missing base dir: $BaseDir" }

$need = @("lenstrans_overlay.exe", "llama.dll", "ggml.dll", "ggml-base.dll", "ggml-cpu.dll")
foreach ($n in $need) {
  if (-not (Test-Path (Join-Path $BaseDir $n))) { throw "missing base file: $n" }
}
Get-ChildItem $BaseDir -Recurse -Filter *.gguf -ErrorAction SilentlyContinue | ForEach-Object {
  throw "GGUF must not be in base MSIX pack: $($_.FullName)"
}

$staging = Join-Path $Root "dist\msix-staging"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

Copy-Item $ManifestSrc (Join-Path $staging "AppxManifest.xml") -Force
foreach ($n in $need) {
  Copy-Item (Join-Path $BaseDir $n) (Join-Path $staging $n) -Force
}
$assets = Join-Path $staging "Assets"
Write-MinimalPng (Join-Path $assets "StoreLogo.png")
Write-MinimalPng (Join-Path $assets "Square150x150Logo.png")
Write-MinimalPng (Join-Path $assets "Square44x44Logo.png")

$packed = $false
$msixBytes = 0L

if ($makeappxPath) {
  New-Item -ItemType Directory -Force -Path (Split-Path $OutMsix) | Out-Null
  if (Test-Path $OutMsix) { Remove-Item $OutMsix -Force }
  & $makeappxPath pack /d $staging /p $OutMsix /o
  if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed exit $LASTEXITCODE" }
  $msixBytes = (Get-Item $OutMsix).Length
  $packed = $true

  if ($TestSign) {
    if (-not $signToolPath) { throw "TestSign requested but signtool not found under $KitsBin" }
    $signInfo = Invoke-TestSignMsix -MsixPath $OutMsix -SignToolPath $signToolPath -PfxPath $pfxPath
    $signed = $true
    $signMode = "test-signed (self-signed sideload; not store/notarized)"
    $signToolNote = "signtool: $signToolPath; cert subject matches AppxManifest Publisher; pfx: dist/test-code-sign.pfx (gitignored)"
    $auth = Get-AuthenticodeSignature -FilePath $OutMsix
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $signToolPath verify /pa $OutMsix 2>&1 | Out-Null
    $verifyExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    $signVerify = "Authenticode: Status=$($auth.Status) Signer=$($auth.SignerCertificate.Subject); signtool verify /pa exit=$verifyExit (untrusted self-signed root expected for test-sign)"
  }
}

$baseBytes = (Get-ChildItem $BaseDir -File | Measure-Object -Property Length -Sum).Sum
$baseDec = Format-DecMb $baseBytes
$basePass = if ($baseBytes -le 30000000) { "PASS" } else { "FAIL" }

$lines = New-Object System.Collections.Generic.List[string]
$null = $lines.Add("# installer size")
$null = $lines.Add("")
$null = $lines.Add("- date: $(Get-Date -Format yyyy-MM-dd)")
$null = $lines.Add("- host: Windows x64")
$null = $lines.Add("- base dir: dist/windows-base/ (exe + llama DLLs, no GGUF)")
$null = $lines.Add("")
$null = $lines.Add("## base (directory)")
$null = $lines.Add("")
$null = $lines.Add("| file | bytes |")
$null = $lines.Add("| --- | ---: |")
Get-ChildItem $BaseDir -File | Sort-Object Name | ForEach-Object {
  $null = $lines.Add("| $($_.Name) | $($_.Length) |")
}
$null = $lines.Add("| **base sum** | **$baseBytes** |")
$null = $lines.Add("")
$null = $lines.Add("- base sum: $baseDec MB (decimal). Limit 30 MB decimal: **$basePass**")
$null = $lines.Add("")
$msixSection = if ($signed) { "## MSIX (test-signed)" } else { "## MSIX (unsigned)" }
$null = $lines.Add($msixSection)
$null = $lines.Add("")
$null = $lines.Add("- makeappx searched: $KitsBin (recursive)")
if ($makeappxPath) {
  $null = $lines.Add("- makeappx found: yes - $makeappxPath")
} else {
  $null = $lines.Add("- makeappx found: no")
}
if ($signed) {
  $null = $lines.Add("- signed: **yes** - $signMode")
  $null = $lines.Add("- verify: $signVerify")
  $null = $lines.Add("- $signToolNote")
  $null = $lines.Add("- production signing: **GOAL_SIGNING_STILL_MISSING** (test-sign only; sideload self-signed, not store/notarized)")
} else {
  $null = $lines.Add("- signed: **no** - UNSIGNED_GOAL_SIGNING_MISSING")
}

if ($packed) {
  $msixRel = $OutMsix.Substring($Root.Length + 1).Replace("\", "/")
  $msixDec = Format-DecMb $msixBytes
  $null = $lines.Add("- msix: dist/$($OutMsix.Substring($OutMsix.LastIndexOf('\') + 1))")
  $null = $lines.Add("- msix bytes: $msixBytes ($msixDec MB decimal)")
  $null = $lines.Add("- pack script: tools/pack/pack-msix.ps1")
} else {
  $null = $lines.Add("- msix: **skipped** (makeappx not found)")
  $null = $lines.Add("- pack script: tools/pack/pack-msix.ps1 (expects Kits makeappx)")
  $null = $lines.Add("- paths searched: $searched")
}

$null = $lines.Add("")
$null = $lines.Add("Install base without MSIX: tools/pack/install-windows.ps1.")

New-Item -ItemType Directory -Force -Path (Split-Path $Report) | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$text = ($lines -join [Environment]::NewLine) `
  -replace "UNSIGNED_GOAL_SIGNING_MISSING", "unsigned; Goal production signing still missing" `
  -replace "GOAL_SIGNING_STILL_MISSING", "Goal production signing still missing"
[System.IO.File]::WriteAllText($Report, $text, $utf8)
$lines | ForEach-Object { Write-Host $_ }

if (-not $makeappxPath) {
  Write-Warning "makeappx not found under $KitsBin"
  exit 2
}

Write-Host "MSIX packed: $OutMsix size=$msixBytes"
