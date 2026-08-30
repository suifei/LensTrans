# LensTrans Windows 轻量打包

自研脚本，不是 Electron / Inno / NSIS / MSIX。双轨：基础包不含 GGUF；完整离线包 = 基础包 + `models/*.gguf`。

## 基础包（≤30MB，不含 GGUF）

```
powershell -File tools/pack/pack-windows.ps1
```

产物：`dist/windows-base/`（exe + llama/ggml DLL）和 `dist/LensTrans-windows-base.zip`。体积写入 `tools/eval/out/installer-size.md`。

装到当前用户目录：

```
powershell -File tools/pack/install-windows.ps1
```

默认目标：`%LOCALAPPDATA%\LensTrans\app`。可选开始菜单快捷方式。不写密钥、不复制 GGUF。

## 完整离线包（≤520MB）

```
powershell -File tools/pack/pack-windows.ps1 -Offline
```

把已有 `models\qwen2.5-0.5b-instruct-q4_k_m.gguf` 拷进 `dist/windows-offline/`。超过 520×10⁶ 字节则失败。

## 不包含

- 491MB GGUF（基础包）
- VC++ 运行库（依赖系统已装的 Universal CRT / 常见 VC 红包）
- 源码、`third_party/llama.cpp` 整树、测试 exe
