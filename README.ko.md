# LensTrans

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · **한국어**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?logo=windows&logoColor=white)](#플랫폼)
[![macOS](https://img.shields.io/badge/macOS-API%20stubs-lightgrey?logo=apple)](#플랫폼)
[![C++](https://img.shields.io/badge/C%2B%2B-20-00599C?logo=cplusplus)](CMakeLists.txt)
[![UI](https://img.shields.io/badge/shell-Win32%20native-informational)](#무엇인가)
[![Engine](https://img.shields.io/badge/local-Qwen2.5--0.5B%20GGUF-orange)](#기능)

**Windows 네이티브 실시간 화면 번역기.** 아무 창 위에 레이어드·클릭 통과 박스를 그립니다. Windows Graphics Capture(WGC)로 픽셀을 잡고, 시스템 OCR로 읽고, 로컬 Qwen2.5-0.5B 또는 직접 넣은 OpenAI 호환 엔드포인트로 번역한 뒤, 몰입 채우기나 스티커로 원문을 가립니다. Electron도 Tauri도 WebView 셸도 쓰지 않습니다.

## 무엇인가

화면 위 글자는 픽셀이지 DOM이 아닙니다. LensTrans는 훅을 걸지 않고, 다른 프로세스의 사설 메모리도 읽지 않습니다. 자기 박스 안만 찍고, 글자를 읽은 다음, 같은 사각형 위에 번역을 그립니다.

```
  ┌─ 대상 창 ────────────────────────────────────────────┐
  │  File   Edit   View                                  │
  │                                                      │
  │    ┌─ LensTrans 박스 (Watching, 클릭 통과) ───────┐  │
  │    │                                              │  │
  │    │   Settings          →    设置                │  │
  │    │   Cancel            →    取消                │  │
  │    │   Please wait…      →    请稍等              │  │
  │    │                                              │  │
  │    └──────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────┘
         트레이  ·  Ctrl+E 편집 / 통과  ·  Esc 종료
```

박스는 `WS_POPUP` 레이어드 HWND(`WS_EX_LAYERED | TOPMOST | TOOLWINDOW`)이며 작업 표시줄에 올리지 않습니다. **Watching**에서는 `WS_EX_TRANSPARENT`를 켜서 클릭이 아래 창으로 빠집니다. **Editing**에서는 통과를 끄고, 제목 표시줄을 끌거나 여덟 방향 12px 핸들로 크기를 바꿉니다. 여러 박스를 지원하며, 박스마다 상태 기계가 있습니다.

```
Hidden → Editing → Watching ⇄ Translating
              Paused ← 어느 상태에서든 (단축키. 캡처는 멈추고, 오버레이는 마지막 프레임을 남김)
```

표시는 두 가지 정직한 방식만 둡니다. 배경 최빈색으로 사각형을 칠한 뒤 번역을 쓰거나(몰입), 불투명 스티커로 원문을 가립니다. 원문이 남은 채 반투명 번역을 겹치는 것은 금지입니다. 대조 모드는 스티커 아래에 60% 크기 원문을 두는 것이지, 글자를 포개지 않습니다. 글자색이 채움 대비 WCAG AA 4.5:1에 못 미치면, 채움의 반전색으로 바꿉니다.

저장소에 제품 스크린샷은 없습니다. 위 그림은 구조도이며, 없는 이미지 URL을 걸지 않기 위해서입니다.

많은 화면 번역은 「비트맵을 잘라 별도 결과 창을 연다」입니다. LensTrans는 **박스를 고정하고, 픽셀 변화를 따라가며, 원문을 덮습니다**.

| | 흔한 팝업형 | LensTrans |
| --- | --- | --- |
| 위치 | 원문에서 떨어진 별도 창 | 직접 그린 픽셀에 박스가 붙음 |
| 시점 | 핫키로 한 장 | 박스 안이 바뀌면 갱신 |
| 오프라인 | 대개 네트워크 필요 | 기본은 로컬 Qwen2.5-0.5B |
| 보임새 | 원문과 번역이 함께 보임 | 몰입 채우기 또는 스티커로 원문을 **가림** |

## 기능

| 영역 | Windows에서 실제로 있는 것 |
| --- | --- |
| 오버레이 | 다중 박스, 최상위, 편집 / 클릭 통과, 트레이 전체 메뉴 |
| 캡처 | WGC(창 세션 / 모니터 크롭). 실패 시 GDI `BitBlt` / `PrintWindow` |
| 프레임 차 | 1/4 다운샘플 + 8×8 SSD. DIFF 없이 약 2초면 휴면, 공회전으로 CPU를 먹지 않음 |
| OCR | STA 스레드의 `Windows.Media.OCR` → 공통 `OcrBlock`(텍스트, bbox, 샘플 색) |
| 안정화 | bbox+text가 같은 연속 2프레임에 300ms 디바운스를 더한 뒤에야 번역으로 넘김 |
| 표시 | 몰입 치환 / 스티커(기본 약 92% 불투명) / 스티커+대조. 반투명 겹쳐 쓰기는 금지 |
| 로컬 번역 | Qwen2.5-0.5B Instruct Q4_K_M, [llama.cpp](https://github.com/ggml-org/llama.cpp) **b10688**(프로세스 내 링크 또는 `llama-cli`) |
| 클라우드 번역 | WinHTTP `POST {base}/chat/completions`. Base URL / Model / API Key **전부 공란**. 비어 있으면 비활성 |
| 키 | DPAPI로 디스크에 저장. 설정 직렬화에 `api_key`가 나오면 안 됨(단위 테스트 있음) |
| UI | 설정 5개 탭, 최초 3단계 안내(안내 중에는 WGC를 켜지 않음) |
| 단축키 | `Ctrl+E` 편집/통과 · `Ctrl+Shift+L` 새 박스 · `Ctrl+T` 일시정지 · `Ctrl+Shift+H` 숨김 · `Ctrl+,` 설정 |

## 빠른 시작

환경: Windows 10 21H2+ 또는 Windows 11, x64, Visual Studio 2022, Windows 10/11 SDK.

1. 이 저장소를 clone합니다. [빌드](#빌드)대로 llama.cpp **b10688**을 받고, [models/README.md](models/README.md)대로 GGUF를 둡니다.
2. `lenstrans_overlay`를 빌드하고 `build\Release\lenstrans_overlay.exe`를 실행합니다.
3. 화면 녹화 권한을 물으면 허용합니다. 영어 UI 위에 박스를 그립니다. `Ctrl+E`로 통과로 바꾼 뒤 아래 창을 클릭합니다.
4. 클라우드를 쓸 때는 설정을 열고 **본인** Base URL, 모델 이름, Key만 넣습니다. 소스에 게이트웨이를 미리 넣지 않습니다.

스크립트 zip(Inno / NSIS / 스토어 서명 패키지가 아님)은 [docs/installer.md](docs/installer.md). 이 트리에는 제품 서명 MSIX가 없습니다.

## 빌드

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

오버레이 안의 로컬 엔진에는 프로세스 내 llama.cpp가 필요합니다.

```bat
git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git third_party\llama.cpp
```

llama.cpp를 **Release x64**로 빌드한 뒤 LensTrans를 다시 구성합니다. CMake는 `third_party/llama.cpp/build/src/Release/llama.lib`를 찾으면 `LENSTRANS_WITH_LLAMA=ON`을 켭니다. 핀 고정은 [third_party/README.md](third_party/README.md).

```
tag:    b10688
commit: c589f0ed10c643678c4707dd160c21ac7633ebc0
remote: https://github.com/ggml-org/llama.cpp.git
```

Ninja + MSVC도 됩니다. vcpkg를 넣지 마세요. UI를 크로스 플랫폼 셸로 바꾸지 마세요.

### 테스트

| 타깃 | 역할 |
| --- | --- |
| `lenstrans_test` | 코어: 캐시, 라우터, 표시, 설정. 주입 프레임 전 구간(WGC 없음) |
| `lenstrans_test_hotkey` | 기본 네 키 `RegisterHotKey` |
| `lenstrans_test_llama` | 선택. GGUF 필요(`--quality-10` / `--quality-30` / `--flores50`) |
| `lenstrans_e2e_target` | overlay 스크립트용 독립 HWND(흰 바탕 `HELLO Settings`) |
| `lenstrans_wgc_probe` | WGC 권한 + OCR 스모크 |

`tools/eval/*.ps1`은 검증 스크립트이며, 보고서는 `tools/eval/out/`에 쓰고 gitignore되어 있습니다. 설명은 [tests/README.md](tests/README.md).

### 패키징

```bat
powershell -File tools\pack\pack-windows.ps1
powershell -File tools\pack\pack-windows.ps1 -Offline
powershell -File tools\pack\install-windows.ps1
```

기본 패키지에는 GGUF가 없습니다. 오프라인 패키지는 기본 + `models/*.gguf`. 상한을 넘으면 스크립트가 실패합니다. 설치 기본 경로는 `%LOCALAPPDATA%\LensTrans\app`. 키는 쓰지 않으며, GGUF를 복사하는 것은 오프라인 패키지를 만든 경우뿐입니다.

## 크기와 메모리 (확정 예산)

제품 제약이지 마케팅 문장이 아닙니다. 판정은 **Working Set(WS)** 로 봅니다. Private Bytes를 「피크 메모리」로 보고하지 않습니다.

| 항목 | 상한 | 설명 |
| --- | --- | --- |
| 기본 패키지 | **≤ 30 MB** | overlay + llama/ggml DLL. **GGUF 없음** |
| 전체 오프라인 | **≤ 520 MB** | 기본 + 공식 Q4_K_M(약 491 MB) + 설치 프로그램 여유 |
| 추론 피크 | **WS ≤ 550 MB** | GGUF 파일 맵 포함 |
| 로컬 상주 | ≤ 600 MB(전형적으로 약 520 MB) | Q4_K_M 고정 후의 물리적 결과 |
| 주 프로세스(가중치 없음) | ≤ 80 MB | 가중치 미로드 |
| 클라우드 상주 | ≤ 120 MB | 클라우드 엔진만 |
| ≤100자 블록 첫 토큰 | ≤ 800 ms | 현대 CPU, 워밍, greedy. 대외 SLO가 아님 |

로컬에서 스크립트 기본 트리는 약 **4.5 MB**(zip 약 1.8 MB), 오프라인 합계 약 **496 MB**로 상한 안이었습니다. 한 대에서 나온 산출물입니다. 툴체인이 바뀌면 숫자는 변하지만 예산은 변하지 않습니다.

기본 가중치: `qwen2.5-0.5b-instruct-q4_k_m.gguf`, 491400032바이트, SHA256 `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`. 받는 절차는 [models/README.md](models/README.md). 고른 이유는 **Apache-2.0이 EU/UK/KR을 포함한 재배포를 허용하기 때문**이지, 0.5B가 전업 기계번역 품질에 도달해서가 아닙니다.

## 개인정보

- **기본은 로컬.** 픽셀은 기기를 나가지 않습니다. OCR은 시스템 엔진, 번역은 로컬 llama.cpp와 직접 받은 GGUF입니다.
- **클라우드 게이트웨이를 미리 넣지 않음.** 소스에 기본 Base URL, 예시 Key, 내장 중계가 없습니다. 세 칸이 다 채워지기 전에는 클라우드가 꺼져 있습니다. 「연결 테스트」만 따로 있습니다.
- API Key는 **DPAPI**만 탑니다. 평문 설정 파일에 넣지 않습니다.
- 캡처는 시스템 API만 씁니다. 주입하지 않고, 다른 프로세스의 사설 메모리도 읽지 않습니다.
- git이 막는 것: `*.gguf`, `*.pfx`, `dist/*.cer`, `third_party/llama.cpp` 전체, `build/`, `.cache/`, `.env`, 비밀류. 올리지 마세요.

## 플랫폼

| | 상태 |
| --- | --- |
| **Windows 10/11 x64** | C++20 + Win32. 이것이 제품입니다. |
| **macOS** | `mac/`는 Swift AppKit **인터페이스 스텁**. [mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md)를 보세요. ScreenCaptureKit / Vision / Metal은 연결되지 않았습니다. 이 저장소에 Xcode 프로젝트는 없습니다. Windows를 먼저 끝냅니다. |

## 제한 (먼저 읽기)

- 기본 로컬 모델은 **0.5B**입니다. 짧은 UI 문장은 종종 쓸 만합니다. 긴 문장과 관용구는 직역이거나 어순이 뒤틀리기 쉽습니다. 용량 한계이지, 「프롬프트만 다듬으면 전업 MT가 된다」가 아닙니다. 정식 FLORES / COMET 평가는 아직 열려 있습니다.
- 이 저장소에는 제품/스토어 코드 서명이 없습니다. `tools/pack/pack-msix.ps1`의 test-sign은 로컬에만 둡니다. 인증서는 커밋하지 않습니다.
- macOS는 배포본이 아닙니다.
- Hunyuan / HY-MT 커뮤니티 라이선스는 EU/UK/KR을 제외합니다. **기본 엔진이 아니며** 설치 패키지에도 넣지 않습니다.

## 디렉터리

```
core/           공유 C++: OcrBlock, 프레임 차, 로컬/클라우드 엔진, 표시, 파이프라인, 설정
win/            overlay, WGC 캡처, WinRT OCR, 트레이와 설정, DPAPI
mac/            Swift 스텁(Windows에서는 컴파일하지 않음)
tests/          단위, e2e 픽스처, WGC 프로브
tools/pack/     zip / MSIX 스크립트
tools/eval/     프로브와 품질 스크립트(out/은 저장소에 넣지 않음)
docs/           설치 프로그램 설명과 M0 문서
models/         GGUF를 둠(가중치는 저장소에 넣지 않음)
third_party/    llama.cpp b10688을 직접 clone(트리는 저장소에 넣지 않음)
```

모듈 표와 고정 제약: [docs/M0-poc-structure.md](docs/M0-poc-structure.md). 모델 라이선스와 평가 계획: [docs/M0-model-eval.md](docs/M0-model-eval.md).

## 라이선스

[MIT](LICENSE) © 2026 flynn (suifei).

선택적 Qwen2.5-0.5B GGUF는 **Apache-2.0**(Alibaba Cloud)입니다. 가중치를 재배포할 때는 해당 라이선스를 함께 두세요. 대조 사본: `tools/eval/licenses/`. llama.cpp는 업스트림 라이선스를 따릅니다. 공식 저장소에서 clone하세요.

## 기여

「네이티브 Windows 화면 번역」에 맞는 이슈와 PR을 환영합니다.

- UI는 Win32 / AppKit에 두세요. Electron, Tauri, Qt, Flutter, WebView를 셸로 넣지 마세요.
- 기본 클라우드 호스트, 예시 API Key, 게이트웨이 상수를 추가하지 마세요.
- `*.gguf`, `*.pfx`, `dist/*.cer`, `third_party/llama.cpp`, `build/`, `.cache/`, 비밀을 커밋하지 마세요.
- 표시 경로에서 「원문이 아직 보이는데 반투명 번역이 겹친다」면 회귀입니다.
- `core/`를 손댔으면 먼저 `lenstrans_test`를 통과시키세요.

평가 도중에 llama.cpp 커밋을 올리지 마세요. 고정은 [third_party/README.md](third_party/README.md).
