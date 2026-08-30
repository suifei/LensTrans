# LensTrans

**中文** · [English](docs/readme/README.en.md) · [日本語](docs/readme/README.ja.md) · [한국어](docs/readme/README.ko.md)

Windows 原生实时屏幕翻译器：在屏幕上划一块透明框，框内原文被译文盖住，而不是再弹一个窗口。默认走本机 Qwen2.5-0.5B；可选自行填写的 OpenAI 兼容接口。不用 Electron，不用 Tauri。

## 和弹窗翻译差在哪

多数屏幕翻译是「截一块 → 弹窗出译文」。LensTrans 把翻译留在原文位置。

| | 弹窗工具 | LensTrans |
| --- | --- | --- |
| 范围 | 整屏或一次截图 | 一块或多块可调框，只译框内 |
| 节奏 | 点一下译一次 | 帧差触发，画面停住就休眠 |
| 呈现 | 另开窗口 | 框内沉浸填充，或贴一条盖住原文 |
| 叠字 | 常见半透明叠在原文上 | **禁止**：必须盖住原文，不能原文译文同时可见 |
| 离线 | 多半要联网 | 默认本地 GGUF；没填云端就不发请求 |
| 运行时 | 常见 Web 壳 | Win32 + C++20 |

macOS 只有接口骨架，**未对等实现**，见 [mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md)。

## 界面

仓库里没有产品截图，下面是 Watching 态的结构，不是假图链接。

```
  目标窗口（浏览器 / 游戏 / PDF）
  ┌──────────────────────────────────────────────┐
  │                                              │
  │   ┌─ 翻译框 ─────────────────────────────┐   │
  │   │ ████████  请稍等                      │   │
  │   │ ████████  （填充或贴条盖住原文）        │   │
  │   └──────────────────────────────────────┘   │
  │                                              │
  └──────────────────────────────────────────────┘
        Watching：点击穿透    Ctrl+E：改框
```

- **沉浸**：用底色填原文区域，只画译文。
- **贴条**：一条不透明带压在原文上。
- **对照**：贴条 + 缩小的原文，仍盖住原位置，不是叠一层半透明字。

## 功能

- 多框：`Ctrl+Shift+L` 再开一块；各框自己的捕获 / OCR / 翻译。
- 捕获：Windows.Graphics.Capture；失败则 GDI BitBlt / PrintWindow。
- OCR：Windows.Media.OCR，变化块并上旧文本邻域；连续两帧稳定后再译。
- 本地引擎：llama.cpp **b10688**，Qwen2.5-0.5B Instruct Q4_K_M。推理峰值 Working Set **≤550MB**。
- 云端：OpenAI 兼容 HTTP。Base URL、API Key、Model **全空**，只提供「测试连接」。Key 走 DPAPI。
- 托盘菜单、五页设置、640×420 三步引导。引导默认勾选「使用本地模型」。

## 安装

本仓库是源码。安装包按两条轨道打包，**不是**二选一产品。

| 轨道 | 内容 | 上限（十进制） |
| --- | --- | --- |
| 基础包 | `lenstrans_overlay.exe` + llama/ggml DLL，**不含** GGUF | **≤30MB** |
| 完整离线包 | 基础包 + 官方 Q4_K_M | **≤520MB**（权重约 491MB，余量给安装器） |

基础包打好后，本地模型有两种来源：把官方 GGUF 放到 `models/`，或直接用离线包。引导里「使用本地模型」默认勾选；权重文件不进 Git。

```
powershell -File tools/pack/pack-windows.ps1
powershell -File tools/pack/pack-windows.ps1 -Offline
powershell -File tools/pack/install-windows.ps1
```

说明见 [docs/installer.md](docs/installer.md)。VC++ / UCRT 当系统依赖，不打进基础包。

默认权重：`qwen2.5-0.5b-instruct-q4_k_m.gguf`（491400032 字节），来自官方 [`Qwen/Qwen2.5-0.5B-Instruct-GGUF`](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF)，Apache-2.0。SHA256：`74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`。放在 [`models/`](models/README.md)。

目标市场含 **EU / UK / KR**，因此默认模型必须是可再分发的 Apache-2.0。Hunyuan / HY-MT 社区协议排除这些地区，不能当默认引擎。

## 从源码构建

需要 Visual Studio 2022、Windows 10 SDK、CMake 3.24+、x64。

1. 按 [third_party/README.md](third_party/README.md) 检出并编译 llama.cpp **b10688**（本仓库不收录该树）。
2. 编译本项目：

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DLENSTRANS_WITH_LLAMA=ON
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

无 llama 预编译库时不要开 `LENSTRANS_WITH_LLAMA`，否则 CMake 会失败。测试说明：[tests/README.md](tests/README.md)。首次弹出屏幕录制权限时点允许。

## 热键

| 热键 | 作用 |
| --- | --- |
| `Ctrl+E` | 编辑框 / 点击穿透 |
| `Ctrl+Shift+L` | 新建翻译框 |
| `Ctrl+T` | 暂停 / 继续 |
| `Ctrl+Shift+H` | 显示或隐藏全部框 |
| `Ctrl+,` | 设置 |
| `Esc` | 退出 |

设置里可改。Watching 态框不挡鼠标。

## 隐私

- 默认本地推理。没填云端三项，进程不会为翻译去访问网络。
- 源码不预填任何公共网关。
- API Key 不进设置明文，只走 DPAPI。
- 捕获只覆盖你划的框，需要系统「屏幕录制」授权。

## 许可

LensTrans 源码为 [MIT](LICENSE)，Copyright 2026 suifei。

Qwen2.5-0.5B 权重是 Apache-2.0（Copyright 2024 Alibaba Cloud），与本仓库 MIT 相互独立。副本：[tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt](tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt)。

## macOS

`mac/` 是 Swift 接口桩，本机 Windows **未编译、未对等**。不做 Electron / Tauri 壳。清单：[mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md)。

## 文档

- [docs/installer.md](docs/installer.md) — 基础包 / 离线包
- [docs/M0-poc-structure.md](docs/M0-poc-structure.md) — 捕获、浮层、管线
- [docs/M0-model-eval.md](docs/M0-model-eval.md) — 模型与内存口径
- [tests/README.md](tests/README.md) — 测试
- [third_party/README.md](third_party/README.md) — llama.cpp b10688
