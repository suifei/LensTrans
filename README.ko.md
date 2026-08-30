# LensTrans

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · **한국어**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?logo=windows&logoColor=white)](#macos)
[![macOS](https://img.shields.io/badge/macOS-stubs-lightgrey?logo=apple)](#macos)
[![C++](https://img.shields.io/badge/C%2B%2B-20-00599C?logo=cplusplus)](CMakeLists.txt)
[![Engine](https://img.shields.io/badge/local-Qwen2.5--0.5B%20GGUF-orange)](#기능)

Windows 네이티브 실시간 화면 번역기입니다. 클릭 통과 투명 박스를 올리고, Windows Graphics Capture(WGC)로 픽셀을 잡고, 시스템 OCR로 읽은 뒤, 로컬 Qwen2.5-0.5B 또는 사용자가 넣은 OpenAI 호환 엔드포인트로 번역하고, 몰입 채우기 또는 스티커로 원문을 가립니다. 결과 창을 따로 띄우는 방식이 아닙니다. Electron / Tauri를 쓰지 않습니다.

## 팝업형과의 차이

많은 화면 번역은 잘라낸 비트맵을 다른 창에 보여 줍니다. LensTrans는 **영역 + 실시간 + 원위치 덮기**입니다.

| | 팝업형 | LensTrans |
| --- | --- | --- |
| 위치 | 원문에서 떨어진 별도 창 | 선택한 영역에 고정된 투명 프레임 |
| 시점 | 핫키로 한 장 | 상자 안 픽셀이 바뀌면 번역 |
| 오프라인 | 대개 네트워크 필요 | 기본은 로컬 Qwen2.5-0.5B |
| 표시 | 원문과 번역이 함께 보임 | **영역 채움(immersive) 또는 띠(sticker)로 원문을 가림. 겹쳐 쓰기 금지** |

반투명 번역을 원문 글자 위에 올리지 않습니다. 배경을 칠한 뒤 번역을 그리거나, 불투명 띠로 원문을 가립니다. 대조 모드는 원문 글자 크기를 줄이고 대비를 맞출 뿐, 두 줄을 겹치지 않습니다.

## 화면 (저장소에 제품 스크린샷 없음)

git에는 제품 스크린샷이 없습니다. 실행 시 대략 다음과 같습니다.

```
  ┌─ 브라우저 / 게임 / PDF ───────────────────────────────┐
  │                                                       │
  │    ┌ LensTrans 상자 ───────────────────────────────┐  │
  │    │ ████ 원문을 덮는 채움                           │  │
  │    │ 잠시만 기다려 주세요                            │  │
  │    │ (immersive 또는 sticker. 글자를 두 겹으로 쓰지 않음) │  │
  │    └───────────────────────────────────────────────┘  │
  │                                                       │
  └───────────────────────────────────────────────────────┘
       Watching 중에는 아래 창으로 클릭 통과    Ctrl+E 로 상자 편집
```

실제 UI는 `build\Release\lenstrans_overlay.exe`를 빌드해 확인하면 됩니다.

## 기능

- **여러 상자:** `Ctrl+Shift+L`로 영역을 추가. 상자마다 캡처 / OCR / 번역.
- **캡처:** `Windows.Graphics.Capture`. 실패 시 GDI `BitBlt` / `PrintWindow`. 프레임 차(1/4 + 8×8 SSD). 정지하면 절전.
- **OCR:** `Windows.Media.OCR` → 공통 `OcrBlock`. 연속 2프레임 안정 + 300ms 디바운스.
- **번역:** 로컬 **Qwen2.5-0.5B Instruct Q4_K_M**(Apache-2.0). 선택적 OpenAI 호환 클라우드.
- **표시:** immersive / sticker / 대조. 채움 대비가 부족하면 글자색을 반전.
- **트레이와 설정:** 트레이 전체 메뉴, 설정 5개 탭, 최초 3단계 안내.
- **비밀:** 클라우드 API 키는 DPAPI. 평문 설정 파일에 넣지 않음.

대상 시장에 **EU / UK / KR**이 포함됩니다. 로컬 기본값은 재배포 가능한 Qwen(Apache-2.0)입니다. 해당 지역을 제외하는 커뮤니티 라이선스 모델은 쓰지 않습니다.

## 설치

이 저장소는 **소스**입니다. 설치 패키지는 이원 규격이며, 둘 중 하나만 제품인 구조가 아닙니다.

| 패키지 | 내용 | 상한 |
| --- | --- | --- |
| **기본** | 런타임(exe + llama/ggml DLL). **GGUF 없음** | **≤30 MB** |
| **전체 오프라인** | 기본 + 같은 공식 Q4_K_M | **≤520 MB** (가중치 약 491 MB, 나머지는 설치 프로그램) |

런타임 피크는 **Working Set ≤550 MB**(매핑된 가중치 포함. Private Bytes로 판정하지 않음).

- 네트워크가 없으면 전체 오프라인 패키지.
- 온라인일 때의 제품 방침: 기본 패키지 후, 첫 실행 안내에서 로컬 모델 사용/받기가 기본(이어받기 + SHA-256 검증 후 확정). 이 git 저장소는 약 491 MB GGUF를 **올리지 않습니다**.
- 소스로 실행할 때: 공식 파일을 `models\qwen2.5-0.5b-instruct-q4_k_m.gguf`에 둡니다. 절차는 [models/README.md](models/README.md).

패키징(먼저 Release 빌드):

```powershell
powershell -File tools/pack/pack-windows.ps1
powershell -File tools/pack/pack-windows.ps1 -Offline
powershell -File tools/pack/install-windows.ps1
```

용량 검사는 [docs/installer.md](docs/installer.md). VC++ / Universal CRT는 시스템 의존성으로 두고 기본 패키지에 넣지 않습니다.

## 소스에서 빌드 (Windows)

**Visual Studio 2022**, Windows 10 SDK, CMake ≥ 3.24, x64.

1. [third_party/README.md](third_party/README.md)대로 `llama.cpp` **b10688**을 받아 빌드합니다. 이 저장소는 그 트리와 빌드 산출물을 포함하지 않습니다.
2. 위의 공식 GGUF를 두거나, 먼저 llama 없이 테스트만 빌드합니다.

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

프로세스 내 로컬 엔진: 미리 빌드한 `llama.lib`가 있으면 CMake가 `LENSTRANS_WITH_LLAMA`를 켭니다. 라이브러리가 없는데 옵션을 강제하지 마세요.

화면 녹화 권한을 물으면 허용하세요. Watching 캡처는 WGC입니다. 안내 창은 탐지 목적으로 캡처 세션을 **시작하지 않습니다**.

## 단축키

| 키 | 동작 |
| --- | --- |
| `Ctrl+E` | 상자 편집 / 클릭 통과(Watching 중에는 아래 창이 맞음) |
| `Ctrl+Shift+L` | 번역 상자 추가 |
| `Ctrl+T` | 일시정지 / 재개 |
| `Ctrl+Shift+H` | 모든 상자 표시 / 숨김 |
| `Ctrl+,` | 설정 |
| `Esc` | 종료 |

트레이 메뉴도 같습니다. 키는 설정에서 바꿀 수 있습니다.

## 개인정보

- **기본은 오프라인.** 로컬 엔진은 화면 글자를 제3자에게 보내지 않습니다.
- **클라우드 게이트웨이를 미리 넣지 않음.** Base URL, API 키, Model은 빈 값이 초기값입니다. 소스에 공개 중계 URL이 없고, 설정에는 「연결 테스트」만 있습니다.
- 키는 DPAPI. `.env`, 인증서, pfx는 git에 넣지 않습니다.
- 캡처는 직접 그린 상자 안으로만 한정됩니다.

## License

[MIT](LICENSE) © 2026 flynn (suifei). 기본 로컬 가중치 Qwen2.5-0.5B Instruct는 **Apache-2.0**(Alibaba Cloud). `llama.cpp`는 업스트림 라이선스를 따릅니다.

## macOS

**동등 구현이 아닙니다.** `mac/`은 Swift 인터페이스 골격입니다. Windows에서는 빌드하지 않으며 완성 앱이 아닙니다. [mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md)를 보세요.

## 기여

Win32 / AppKit을 유지하세요. Electron / Tauri를 넣지 마세요. 기본 클라우드 호스트나 Key를 추가하지 마세요. `*.gguf` / `*.pfx` / `third_party/llama.cpp` / `build/`를 커밋하지 마세요. `core/`를 바꾸면 `lenstrans_test`를 통과시키세요.
