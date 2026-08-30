# macOS（SPM）

```bash
cd mac
swift test                              # LogicTests
swift build -c release --product LensTrans
bash ../tools/eval/mac-smoke.sh         # 本机门禁
./.build/release/LensTrans              # 托盘 LT
```

状态与缺口见 `UNIMPLEMENTED.md` / `docs/mac-dev-status.md`。

约束与 Windows 相同：无 Electron/Tauri；云端不预填网关；默认 Qwen2.5-0.5B Q4_K_M；呈现禁止半透明叠字。
