# Goal verify (PRD v0.2)

- date: 2026-08-30T16:28:03Z
- host: Linux 6.12.94+
- root: `/workspace`

| item | auto | status | evidence |
| --- | --- | --- | --- |
| no Electron/Tauri/Hunyuan deps | yes | **pass** | clean |
| offline budget arithmetic | yes | **pass** | 520e6 - 491400032 = 28599968 (installer headroom) |
| GGUF SHA256 lock | yes | **pass** | model_meta.hpp / ModelMetaLogic 74a4da8c… |
| lenstrans_test (cache/route/present/cloud) | yes | **pass** | test_core: all checks passed |
| mac-logic-verify.py | yes | **pass** | tools/eval/mac-logic-verify.py |
| swift test LensTransLogic | yes | **pass** | exit=0; 7 tests |
| macOS 接口+未实现清单 | doc | **pass** | mac/UNIMPLEMENTED.md |
| WGC capture e2e | yes | **blocked** | requires Windows host + Release build |
| OCR WinRT e2e | yes | **blocked** | requires Windows host + Release build |
| overlay transparent/click-through | yes | **blocked** | requires Windows host + Release build |
| hotkey RegisterHotKey probe | yes | **blocked** | requires Windows host + Release build |
| overlay multi-box e2e | yes | **blocked** | requires Windows host + Release build |
| base pack ≤30MB (Release binaries) | yes | **blocked** | requires Windows host + Release build |
| offline pack ≤520MB (with GGUF) | yes | **blocked** | requires Windows host + Release build |
| WS ≤550MB (llama load) | yes | **blocked** | requires Windows host + Release build |
| mvp-auto.ps1 all-green | yes | **blocked** | requires Windows host + Release build |
| W1/FLORES formal | no | **fail** | out of MVP-auto scope / missing by design |
| Mac device e2e | no | **fail** | out of MVP-auto scope / missing by design |
| 8h soak | no | **fail** | out of MVP-auto scope / missing by design |
| signed MSIX | no | **fail** | out of MVP-auto scope / missing by design |

- auto_fail: 0
- auto_blocked_need_windows: 9
- goal_complete: **no**

Windows MVP-auto (`tools/eval/mvp-auto.ps1`) remains the authoritative gate for
overlay/WGC/OCR/pack/WS items. This host cannot substitute that evidence.
