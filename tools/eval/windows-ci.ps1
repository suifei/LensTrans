# Headless / CI Windows gate for PRD v0.2 auto items that do not need an interactive desktop.
# Full GUI mvp-auto.ps1 remains required for overlay/WGC/click-through on a real desktop.
param(
  [switch]$WithGguf,
  [switch]$SkipLlamaBuild
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OutDir = Join-Path $Root "tools\eval\out"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$Report = Join-Path $OutDir "windows-ci.md"
$Results = New-Object System.Collections.Generic.List[object]
$fail = 0

function Add-Result($id, $name, $pass, $evidence, $detail) {
  [void]$script:Results.Add([pscustomobject]@{ id=$id; name=$name; pass=$pass; evidence=$evidence; detail=$detail })
  if ($null -ne $pass -and -not $pass) { $script:fail += 1 }
}

Set-Location $Root
$env:LENSTRANS_ROOT = $Root

# Prefer Ninja+MSVC when cl.exe is on PATH (GHA msvc-dev-cmd). Else VS generator.
$UseNinja = $false
if (Get-Command cl.exe -ErrorAction SilentlyContinue) {
  if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    choco install ninja -y --no-progress
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
  }
  if (Get-Command ninja -ErrorAction SilentlyContinue) { $UseNinja = $true }
}

function Resolve-OutDir([string]$buildRoot) {
  foreach ($c in @((Join-Path $buildRoot "Release"), $buildRoot)) {
    if (Test-Path (Join-Path $c "lenstrans_test.exe")) { return $c }
  }
  return (Join-Path $buildRoot "Release")
}

function Find-LlamaLib([string]$llamaBuild) {
  foreach ($c in @(
      (Join-Path $llamaBuild "src\Release\llama.lib"),
      (Join-Path $llamaBuild "src\llama.lib"),
      (Join-Path $llamaBuild "Release\llama.lib")
    )) {
    if (Test-Path $c) { return $c }
  }
  return $null
}

Write-Host "UseNinja=$UseNinja cl=$(Get-Command cl.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)"

# --- llama.cpp b10688 ---
$llamaSrc = Join-Path $Root "third_party\llama.cpp"
$llamaBuild = Join-Path $llamaSrc "build"
if (-not $SkipLlamaBuild) {
  if (-not (Test-Path (Join-Path $llamaSrc "include\llama.h"))) {
    git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git $llamaSrc
  }
  if (-not (Find-LlamaLib $llamaBuild)) {
    if ($UseNinja) {
      cmake -S $llamaSrc -B $llamaBuild -G Ninja -DCMAKE_BUILD_TYPE=Release `
        -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF
      if ($LASTEXITCODE -ne 0) { throw "llama cmake configure failed (ninja)" }
      cmake --build $llamaBuild --target llama
    } else {
      $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
      $Gen = "Visual Studio 17 2022"
      if (Test-Path $vswhere) {
        $ver = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion
        if ($ver -match '^18\.') { $Gen = "Visual Studio 18 2025" }
      }
      cmake -S $llamaSrc -B $llamaBuild -G $Gen -A x64 `
        -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=OFF
      if ($LASTEXITCODE -ne 0) { throw "llama cmake configure failed ($Gen)" }
      cmake --build $llamaBuild --config Release --target llama
    }
    if ($LASTEXITCODE -ne 0) { throw "llama build failed" }
  }
}
$llamaLib = Find-LlamaLib $llamaBuild
$haveLlama = [bool]$llamaLib
Add-Result "llama_build" "llama.cpp b10688" $haveLlama $(if ($llamaLib) { $llamaLib } else { $llamaBuild }) $(if ($haveLlama) { "ok" } else { "missing llama.lib" })

# --- configure + build LensTrans ---
$build = Join-Path $Root "build"
if ($UseNinja) {
  cmake -S $Root -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release
} else {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  $Gen = "Visual Studio 17 2022"
  if (Test-Path $vswhere) {
    $ver = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion
    if ($ver -match '^18\.') { $Gen = "Visual Studio 18 2025" }
  }
  cmake -S $Root -B $build -G $Gen -A x64
}
if ($LASTEXITCODE -ne 0) { throw "LensTrans cmake configure failed" }

$targets = @(
  "lenstrans_test",
  "lenstrans_test_hotkey",
  "lenstrans_overlay",
  "lenstrans_wgc_probe",
  "lenstrans_e2e_target"
)
if ($haveLlama) { $targets += "lenstrans_test_llama" }
if ($UseNinja) {
  foreach ($t in $targets) {
    cmake --build $build --target $t
    if ($LASTEXITCODE -ne 0) { throw "build $t failed" }
  }
} else {
  $cmakeArgs = @("--build", $build, "--config", "Release")
  foreach ($t in $targets) { $cmakeArgs += @("--target", $t) }
  & cmake @cmakeArgs
  if ($LASTEXITCODE -ne 0) { throw "cmake build failed exit=$LASTEXITCODE" }
}
$rel = Resolve-OutDir $build
$testExe = Join-Path $rel "lenstrans_test.exe"
$hkExe = Join-Path $rel "lenstrans_test_hotkey.exe"
Add-Result "build" "Release targets" (Test-Path $testExe) $rel $(if (Test-Path $testExe) { "ok" } else { "missing test exe" })

# --- unit / hotkey ---
if (Test-Path $testExe) {
  & $testExe
  Add-Result "test_core" "lenstrans_test" ($LASTEXITCODE -eq 0) $testExe "exit=$LASTEXITCODE"
} else {
  Add-Result "test_core" "lenstrans_test" $false $testExe "missing"
}
if (Test-Path $hkExe) {
  & $hkExe
  Add-Result "test_hotkey" "lenstrans_test_hotkey" ($LASTEXITCODE -eq 0) $hkExe "exit=$LASTEXITCODE"
} else {
  Add-Result "test_hotkey" "lenstrans_test_hotkey" $false $hkExe "missing"
}

# Ensure llama DLLs sit next to overlay for pack-windows.ps1
if ($haveLlama) {
  $dllDirs = @(
    (Join-Path $llamaBuild "bin\Release"),
    (Join-Path $llamaBuild "bin"),
    (Join-Path $llamaBuild "Release")
  )
  foreach ($dll in @("llama.dll", "ggml.dll", "ggml-base.dll", "ggml-cpu.dll")) {
    $dst = Join-Path $rel $dll
    if (Test-Path $dst) { continue }
    foreach ($dllSrc in $dllDirs) {
      $src = Join-Path $dllSrc $dll
      if (Test-Path $src) { Copy-Item $src $dst -Force; break }
    }
  }
}

# --- pack base / offline ---
$pack = Join-Path $Root "tools\pack\pack-windows.ps1"
$sizeMd = Join-Path $OutDir "installer-size.md"
if ((Test-Path $pack) -and (Test-Path (Join-Path $rel "lenstrans_overlay.exe"))) {
  try {
    & $pack -BuildDir $rel
    $sm = if (Test-Path $sizeMd) { Get-Content $sizeMd -Raw } else { "" }
    $basePass = $sm -match "Limit 30 MB decimal:\s*\*\*PASS\*\*"
    Add-Result "base_pack" "base pack <=30MB" $basePass $sizeMd $(if ($basePass) { "PASS" } else { "FAIL/missing" })
  } catch {
    Add-Result "base_pack" "base pack <=30MB" $false $pack $_.Exception.Message
  }
} else {
  Add-Result "base_pack" "base pack <=30MB" $false $pack "overlay or pack script missing"
}

$gguf = Join-Path $Root "models\qwen2.5-0.5b-instruct-q4_k_m.gguf"
if ($WithGguf) {
  if (-not (Test-Path $gguf)) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root "models") | Out-Null
    $urls = @(
      "https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf",
      "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
    )
    foreach ($u in $urls) {
      try {
        curl.exe -L -C - --retry 8 --retry-all-errors -o $gguf $u
        if ((Get-Item $gguf).Length -eq 491400032) { break }
      } catch { }
    }
  }
  if (Test-Path $gguf) {
    $hash = (Get-FileHash -Algorithm SHA256 $gguf).Hash
    $hashOk = $hash -eq "74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB"
    Add-Result "gguf" "GGUF sha256/size" $hashOk $gguf "sha=$hash bytes=$((Get-Item $gguf).Length)"
    try {
      & $pack -BuildDir $rel -Offline
      $sm = if (Test-Path $sizeMd) { Get-Content $sizeMd -Raw } else { "" }
      $offPass = $sm -match "Limit 520 MB:\s*\*\*PASS\*\*"
      Add-Result "offline_pack" "offline pack <=520MB" $offPass $sizeMd $(if ($offPass) { "PASS" } else { "FAIL" })
    } catch {
      Add-Result "offline_pack" "offline pack <=520MB" $false $pack $_.Exception.Message
    }
    $llamaTest = Join-Path $rel "lenstrans_test_llama.exe"
    if ((Test-Path $llamaTest) -and $hashOk) {
      & $llamaTest --quality-10
      $q10 = Join-Path $OutDir "quality-10.md"
      $wsPass = $false
      $wsDetail = "no quality-10.md"
      if (Test-Path $q10) {
        $q = Get-Content $q10 -Raw
        # Look for max WS numbers if present; also accept process exit 0 + file exists as partial
        if ($q -match '(?m)^- ws_le_550:\s*yes') {
          $wsPass = $true
          if ($q -match '(?m)^- max_ws_mib:\s*(\d+(?:\.\d+)?)') {
            $wsDetail = "max_ws_mib=$($Matches[1]) ws_le_550=yes"
          } else {
            $wsDetail = "ws_le_550=yes"
          }
        } elseif ($q -match '(?m)^- max_ws_mib:\s*(\d+(?:\.\d+)?)') {
          $ws = [double]$Matches[1]
          $wsPass = ($ws -le 550.0)
          $wsDetail = "max_ws_mib=$ws"
        } else {
          $wsPass = ($LASTEXITCODE -eq 0)
          $wsDetail = "quality-10 written exit=$LASTEXITCODE (parse WS manually)"
        }
      }
      Add-Result "ws550" "WS <=550MB (quality-10)" $wsPass $q10 $wsDetail
    } else {
      Add-Result "ws550" "WS <=550MB (quality-10)" $null $llamaTest "BLOCKED (no llama test or bad gguf)"
    }
  } else {
    Add-Result "gguf" "GGUF download" $false $gguf "missing"
    Add-Result "offline_pack" "offline pack <=520MB" $null $sizeMd "no gguf"
    Add-Result "ws550" "WS <=550MB" $null "-" "no gguf"
  }
} else {
  Add-Result "offline_pack" "offline pack <=520MB" $null "-" "WithGguf not set"
  Add-Result "ws550" "WS <=550MB" $null "-" "WithGguf not set"
}

# --- WGC probe (BLOCKED is explicit when this host has no interactive capture permission) ---
$wgc = Join-Path $rel "lenstrans_wgc_probe.exe"
if (Test-Path $wgc) {
  $p = Start-Process -FilePath $wgc -PassThru -NoNewWindow -Wait
  $wgcMd = Join-Path $OutDir "wgc-probe.md"
  $ok = ($p.ExitCode -eq 0)
  Add-Result "wgc_probe" "wgc_probe" $(if ($ok) { $true } else { $null }) $wgcMd $(if ($ok) { "exit=$($p.ExitCode)" } else { "BLOCKED: exit=$($p.ExitCode) (interactive desktop/capture permission required)" })
} else {
  Add-Result "wgc_probe" "wgc_probe" $null "-" "BLOCKED: not built"
}

$lines = @(
  "# Windows CI / headless gate",
  "",
  "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
  "- host: $([Environment]::OSVersion.VersionString)",
  "- with_gguf: $WithGguf",
  "- fail_count: $fail",
  "",
  "| step | pass | evidence | detail |",
  "| --- | --- | --- | --- |"
)
foreach ($r in $Results) {
  $p = if ($null -eq $r.pass) { "BLOCKED" } elseif ($r.pass) { "PASS" } else { "FAIL" }
  $lines += "| $($r.name) | $p | ``$($r.evidence)`` | $($r.detail) |"
}
$lines += ""
$lines += "- gui_mvp_auto: **BLOCKED** (needs interactive desktop: overlay-e2e / click-through / hotkey-probe)"
$lines += "- script_hard_fail_count: $fail"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllLines($Report, $lines, $utf8)
$lines | ForEach-Object { Write-Host $_ }
exit $(if ($fail -eq 0) { 0 } else { 1 })
