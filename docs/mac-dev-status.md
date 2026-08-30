# macOS 开发与本机验证说明

## 项目目录

推荐本机路径：

```bash
mkdir -p ~/works
# 已有 clone 时：
cd ~/works/LensTrans
# 或：
git clone <repo-url> ~/works/LensTrans
cd ~/works/LensTrans/mac
```

Cloud Agent 同步副本：`/home/ubuntu/works/LensTrans`（与 `/workspace` 同内容）。

## 本环境已跑通的验证（2026-08-30）

| 检查 | 结果 | 命令/证据 |
| --- | --- | --- |
| mac 纯逻辑镜像 | PASS | `python3 tools/eval/mac-logic-verify.py` |
| C++ `lenstrans_test` | PASS | Linux cmake build |
| Swift `swift test` | 本机无 Swift/SDK | 需在 macOS 上 `cd mac && swift test` |
| AppKit / ScreenCaptureKit / Vision e2e | 未跑 | 需 macOS 真机 |

## macOS 上完整测试

```bash
cd ~/works/LensTrans/mac
swift test
swift build -c release --product LensTrans
# 运行后：托盘 LT → 引导三步（勿在步骤 2 启 SCStream）→ 拉框 → 授权屏幕录制
```

未完成（见 `mac/UNIMPLEMENTED.md`）：llama.cpp Metal 链接、安装器、真机 Capture→OCR→Present 签字验收。
