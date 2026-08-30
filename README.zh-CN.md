# LensTrans

**原位盖住屏幕上的字。原生浮层。默认本地。**

[English](README.md) · [简体中文](README.zh-CN.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-native-0b57d0)](#从源码构建windows)
[![macOS](https://img.shields.io/badge/macOS-unimplemented-lightgrey)](mac/UNIMPLEMENTED.md)

框住一块屏幕，做 OCR，用实心底色或贴条盖住原文。不用 Electron / Tauri，也不做半透明叠字。

Windows（Win32）是可用端口。macOS 只有接口桩，见 [`mac/UNIMPLEMENTED.md`](mac/UNIMPLEMENTED.md)。

## 功能

- 透明框：编辑、缩放、多框、Watching 时点击穿透
- 呈现：沉浸替换、贴条、可选对照。禁止纯透明叠字
- 本地 **Qwen2.5-0.5B Instruct Q4**（Apache-2.0），llama.cpp **b10688**
- 可选 OpenAI 兼容云端。Base URL / 模型 / Key 默认全空，不预填公共网关。Key 走 DPAPI
- 托盘、设置（5 个 Tab）、首次 3 步引导、热键
- 双轨分发：基础包 **≤30MB**（首启下载 GGUF）；完整离线包 **≤520MB**

默认热键：`Ctrl+E` 编辑/穿透 · `Ctrl+Shift+L` 新框 · `Ctrl+T` 暂停 · `Ctrl+Shift+H` 全隐 · `Ctrl+,` 设置 · `Esc` 退出。

仓库里没有产品截图。评测脚本把记录写到 `tools/eval/out/`（不入库）。

## 安装（Windows）

Release 构建后打包（见 [docs/installer.md](docs/installer.md)）：

```
powershell -File tools/pack/pack-windows.ps1
powershell -File tools/pack/install-windows.ps1
```

离线包（需要 `models/qwen2.5-0.5b-instruct-q4_k_m.gguf`）：

```
powershell -File tools/pack/pack-windows.ps1 -Offline
```

GGUF 不进 git。放到 `models/` 并核对 SHA-256，见 [models/README.md](models/README.md)。

## 从源码构建（Windows）

Visual Studio 2022 + Windows 10 SDK，x64。先按 [third_party/README.md](third_party/README.md) 浅克隆 llama.cpp **b10688**，再：

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

预编译库存在时会打开进程内 llama（`LENSTRANS_WITH_LLAMA`）。若系统弹出屏幕录制权限，点允许。

## macOS

与 Windows 不对等。`mac/` 是桩，CMake 不编 Swift。清单：[mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md)。

## 隐私

默认本地推理。只有你填了 Base URL、模型和 Key 才会走云端。源码不内置网关主机。API Key 用 DPAPI 落盘，不写日志。

## 许可

- 本仓库源码：[MIT](LICENSE)，Copyright 2026 suifei
- 下载的 Qwen2.5-0.5B Instruct GGUF：[Apache-2.0](tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt)（Alibaba Cloud）
- llama.cpp（需自行克隆）：MIT，tag `b10688`

## 贡献与安全

欢迎针对 Windows 路径提 issue / PR。不要提交 `*.gguf`、`*.pfx`、`settings.cfg` 或密钥。不要把 API Key 贴进 issue 或 PR。

## 文档

- [docs/M0-poc-structure.md](docs/M0-poc-structure.md)
- [docs/installer.md](docs/installer.md)
- [docs/M0-model-eval.md](docs/M0-model-eval.md)
- [tests/README.md](tests/README.md)
