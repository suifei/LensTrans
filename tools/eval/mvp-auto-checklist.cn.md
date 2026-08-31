| Goal 项 | 可自动 | 状态 | 硬证据 |
| --- | --- | --- | --- |
| 透明框（分层/拖拽/穿透） | partial | {{transparent}} | overlay-e2e COVER_OK; click-through hit_test=target（Agent SendInput skip） |
| WGC 捕获 | yes | {{wgc}} | tools/eval/out/wgc-probe.md; overlay-wgc-monitor.md; overlay-wgc-window.md |
| OCR (WinRT STA) | yes | {{ocr}} | wgc_probe mem_ok; overlay OCR HELLO Settings |
| 本地 Qwen2.5-1.5B | partial | {{qwen}} | quality-10.md; overlay-llama-e2e.md |
| 云端 OpenAI 兼容 mock/SSE | yes | {{cloud}} | tests/test_core.cpp ParseChatCompletionBody RouteEngine |
| 托盘/设置/引导/热键 | partial | {{hotkey}} | lenstrans_test_hotkey RegisterHotKey; hotkey-probe.md WM_HOTKEY |
| 沉浸/贴条盖原文 | yes | {{present}} | test_core inject; overlay-e2e COVER_OK+PRESENT |
| 多框 | partial | {{multibox}} | test_core SerializeBoxes; overlay-two-box.md |
| 缓存/路由 | yes | {{cache}} | test_core cache RouteEngine DispatchTranslate |
| 基础包 <=30MB | yes | {{base}} | tools/eval/out/installer-size.md |
| 离线包 <=520MB | if gguf | {{offline}} | tools/eval/out/installer-size.md |
| WS <=550MB | partial | partial | quality-10 max ~482.7 MiB; overlay-llama ~542 MiB |
| macOS 接口清单 | doc | pass | mac/UNIMPLEMENTED.md vs 11 swift stubs |
| W1 / FLORES | no | fail | 缺失 |
| Mac 真机 | no | fail | 缺失 |
| 8h 挂机 | no | fail | 缺失 |
| 签名 MSIX | no | fail | 缺失 |
