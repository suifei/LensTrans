# M0 PoC 代码结构（捕获 / 穿透窗口）

对齐 PRD v0.2 §3–§5。本阶段 **Windows 可编译** 为硬交付；macOS 只定接口。禁止 Electron / Tauri / CEF / WebView 壳。呈现禁止纯透明叠字（原文译文重叠）。

已拍板：模型双轨分发（基础包 ≤30MB，完整离线包 **≤520MB**：官方 Qwen2.5-0.5B Q4_K_M 约 491MB，余量给安装器，首启下载不变）；云端 Base URL / API Key / Model 留空；目标市场含 EU/UK/KR；本地默认引擎为 **Qwen2.5-0.5B Instruct Q4 GGUF（Apache-2.0）**——因许可可再分发，不是因为质量已测完。推理峰值 **Working Set ≤550MB**（含权重映射；验收看 WS 不看 Private Bytes）。本地模式常驻总量 ≤600MB，典型约 520MB（取代原 ≤450 / 典型 320，是锁 Q4_K_M 后的物理后果）。主进程不含模型 ≤80MB、云端常驻 ≤120MB、首字 800ms 未改。Hunyuan / HY-MT 社区许可硬出局。源码不预填网关常量。API Key 只走 DPAPI 落盘。

## 1. 目录树（2026-08-30 已落地）

```
LensTrans/
  CMakeLists.txt
  core/include/lenstrans/     # ocr_block / frame_diff / cache / router / present / pipeline / settings / engine
  core/src/engine_local.cpp   # llama-cli（默认）或 LENSTRANS_WITH_LLAMA 进程内
  core/src/engine_cloud.cpp   # WinHTTP OpenAI 兼容，无默认 host
  win/overlay/main.cpp        # 多框 + 管线线程 + 沉浸/贴条
  win/capture/capture.cpp     # WGC → BitBlt → PrintWindow
  win/ocr/winrt_ocr.cpp       # Windows.Media.OCR → OcrBlock
  win/app/ui.cpp              # 托盘完整树 + 设置 5 Tab + 3 步引导
  win/app/secrets.cpp         # DPAPI + 开机自启
  mac/*.swift + UNIMPLEMENTED.md   # 接口骨架，本机 Windows 不编译
  tools/pack/pack-windows.ps1     # 基础包（无 GGUF）/ 离线包
  tools/eval/ws-probe.ps1         # 60–120s WS 采样，不是 8h
  tests/test_core.cpp
  docs/M0-model-eval.md
  docs/M0-poc-structure.md
  docs/installer.md
```

## 2. 模块职责

| 模块 | 职责 | 不做 |
| --- | --- | --- |
| `win/overlay` | 框的 HWND：分层、置顶、不占任务栏、编辑态命中、Watching 点击穿透 | 不画译文、不捕获 |
| `win/capture` | 框矩形 → BGRA 帧。主路径 WGC；失败降 PrintWindow | 不做全局 hook / 驱动 |
| `core/frame_diff` | 变化块掩码，静止 ≥2s 休眠 | 不在 UI 线程做重计算 |
| `win/ocr` / `mac/Ocr` | 系统 OCR → `OcrBlock` | 不在 M0/M1 链 Paddle（P2 兜底） |
| `core/engine` | llama.cpp：load / infer / unload。云端是另一个 HTTP 后端，配置全空 | 不预填 URL、不内置 key |
| `win/render` | 沉浸替换 > 贴条 > 贴条+对照。底色填充或贴条盖住原文 | 禁止只调 alpha 叠字 |

框状态机（每框一份）：

```
Hidden → Editing → Watching ⇄ Translating
Paused ← 任意态（热键），停止捕获，浮层保留最后一帧结果
```

PoC 只实现 `Editing` / `Watching`（穿透）。`Translating` / `Paused` / `Hidden` 在 M1 接上捕获后补。

## 3. 平台 API 映射（写死，禁止换成跨平台 UI）

### Windows（C++20 + Win32）

| 能力 | API | 要点 |
| --- | --- | --- |
| 窗口 | `CreateWindowExW` | `WS_POPUP` + `WS_EX_LAYERED \| TOPMOST \| TOOLWINDOW` |
| 穿透 | `WS_EX_TRANSPARENT` | Watching 打开；Editing 清掉。可叠加 `WS_EX_NOACTIVATE` |
| 像素透明 | `UpdateLayeredWindow` + 预乘 ARGB | 后续 D2D 仍走分层表面，不要 `SetLayeredWindowAttributes` 整窗匀 alpha 当最终方案 |
| 合成 | Direct2D + DirectComposition | 译文层 60fps，只重绘脏块 |
| 捕获 | `Windows.Graphics.Capture`（1903+，目标 21H2+） | 会话绑框矩形所在屏幕；显示器热插拔重建 |
| 捕获兜底 | `PrintWindow` + `PW_RENDERFULLCONTENT` | WGC 对部分全屏/受保护内容失败时用；失败则该块跳过 |
| OCR | `Windows.Media.Ocr.OcrEngine` | 映射进 `OcrBlock` |
| DPI | Per-Monitor V2 | `WM_DPICHANGED` 重建坐标 |

当前 `win/overlay/main.cpp` 已覆盖：分层置顶、编辑拖拽、8 个 12px 把手、Ctrl+E 穿透、WGC/PrintWindow、帧差可视化、OCR 调试叠层、沉浸/贴条（禁止纯透明叠字）、多框、托盘与热键。坐标用物理像素（Per-Monitor V2）。

### macOS（Swift 5.9 + AppKit，本阶段不编译）

| 能力 | API |
| --- | --- |
| 窗口 | `NSPanel` `.nonactivatingPanel` + `.borderless`，`level = .statusBar` |
| 穿透 | `ignoresMouseEvents = true` |
| 捕获 | ScreenCaptureKit（12.3+） |
| OCR | Vision `VNRecognizeTextRequest`（中英日韩） |

接口桩见 `mac/OverlayPanel.swift`。Xcode 工程放到 M1，不在 CMake 里用 `add_executable` 混编 Swift。

## 4. 共享 C++ 翻译核（目录规划，M0 不实现）

```
core/
  include/lenstrans/
    ocr_block.hpp      # 已有
    engine.hpp         # M1：LocalEngine / CloudEngine
    frame_diff.hpp
  src/
    engine_local.cpp   # llama_model_load_from_file
                       # 默认权重：Qwen2.5-0.5B Instruct Q4 GGUF
                       # n_ctx=1024, n_batch=512
                       # KV 常驻；空闲 10min 卸载（M1）
    engine_cloud.cpp  # POST {base_url}/chat/completions SSE
                       # 三个字段用户填什么用什么；空则禁用云端
```

约束：

- 只链接 llama.cpp 为静态或私有共享库，版本与评测定版 commit 一致。
- 不要在核里写死 Hugging Face 仓库名以外的下载逻辑；下载器属于首启引导（M1）。
- DirectML 是可选加速，M0/M1 验收以 CPU `n_gpu_layers=0` 为准。

## 5. OCR 统一结构体

```cpp
// core/include/lenstrans/ocr_block.hpp
struct OcrBlock {
  std::string text;
  BBox bbox;          // DIP，捕获区左上为原点
  float line_height;
  ColorRgb color;     // 原文字色采样
  float bg_variance;  // 文本块内/环带色彩方差；低于阈值 → 沉浸替换
};
```

两端 OCR 适配器只允许做字段填充，不准再定义第二套「富文本块」。渲染：

1. `bg_variance` 低且静止 → 众数色填矩形（2px 羽化）再画译文
2. 否则贴条（默认不透明 92%）
3. 用户开对照 → 贴条下 60% 字号原文
4. **禁止** 在原文上直接画半透明字

## 6. 编译入口

Windows（VS 2022 + Windows 10/11 SDK，x64）：

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
# 产物：build/Release/lenstrans_overlay.exe
```

Ninja + MSVC 亦可。不要加 vcpkg 依赖。macOS 本阶段无编译入口。

## 7. 最小可运行里程碑

分四档。M0 结束必须到 **M0-A**；M0-B/C 能做则做，做不完不得阻塞模型评测。

| 档 | 行为 | 验收 |
| --- | --- | --- |
| **M0-A** | 启动即 Editing；拖顶栏、8 向缩放；Ctrl+E Watching 穿透；Esc 退出 | **已验收编译**：`build/Release/lenstrans_overlay.exe` |
| **M0-B** | 框客户区 WGC，失败 BitBlt/PrintWindow；1/4 下采样 8×8 SSD；变化打日志并黄块可视化 | **代码已接并编译**。需人工：拖记事本进框看 `DIFF` 日志。首启 WGC 可能弹屏幕录制权限，点允许 |
| **M0-C** | WinRT OCR 只跑变化∪旧块膨胀区；连续 2 帧稳定才提交；框内画 bbox+text（调试层） | **代码已接并编译**。0 块打印 `OCR_EMPTY`。需人工：英文 PDF/设置页 |
| **M1** | 沉浸/贴条盖原文；本地 Qwen（llama-cli b10688）；托盘；3 步引导；热键 | **骨架已编译**。未加载模型时 exe WS ~14MB（≤80MB）。翻译走已编 `llama-cli` |
| **M2** | 设置 5 Tab、云端（空配置禁用，DPAPI）、缓存 sha1、多框 | **骨架已编译**。云端不预填网关。`test_core` 覆盖路由/缓存/呈现/设置序列化 |

管线预算（实现 M0-B/C 时对照，不要在 UI 线程做 OCR）：

```
≤15fps 捕获 → 帧差 ~3ms → OCR（变化∪邻域）→ 连续 2 帧 bbox+text 一致 → 去抖 300ms
→ 翻译队列（M1）→ 脏矩形合成
```

## 8. 硬约束清单（Code review 用）

- 不得引入 Electron、Tauri、Qt、Flutter、wxWidgets、WebView2 作为 UI 壳
- 不得在源码里写 Base URL / 默认模型名 / 示例 API Key
- 不得把 GGUF 提交进 git
- 呈现路径若出现「原文仍可见且译文叠加上去」，视为功能回归
- 捕获只用系统 API；不做注入、不读其他进程私有内存
- 多框状态机独立；Windows 已支持多 HWND

## 9. 本机验证

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

2026-08-30：`lenstrans_test` 全绿。`lenstrans_test_llama` 进程内 b10688：热态首字 343ms、WS 479MiB、输出含中文（字面）。overlay 已链同一套 llama DLL。GGUF 491400032 字节 ≤520MB 离线包。

手工：Ctrl+E 穿透点下层；框住英文 UI 看控制台 `DIFF`/`OCR`；托盘可新建框/改引擎/开设置。若弹出屏幕录制权限，点允许。不要把 GGUF 或 `.env` 提交进 git。
