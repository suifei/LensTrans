# macOS（SPM）

```bash
# 建议路径（本机）
mkdir -p ~/works && git clone <repo> ~/works/LensTrans
cd ~/works/LensTrans/mac

swift test          # 纯逻辑（Present / 路由 / SSE 解析 / 模型元数据）
# 下列需要完整 macOS SDK：
swift build -c release --product LensTrans
```

约束与 Windows 相同：无 Electron/Tauri；云端不预填网关；默认 Qwen2.5-0.5B Q4_K_M；呈现禁止半透明叠字。
