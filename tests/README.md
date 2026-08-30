# 测试

```
cmake --build build --config Release --target lenstrans_test
.\build\Release\lenstrans_test.exe
```

`lenstrans_test` 含注入帧全链路（合成 BGRA，不走 WGC）：帧差 → 假 OCR → 稳定 2 帧 → 缓存/路由/翻译 → 沉浸/贴条决策，并断言禁止「半透明叠字」。可选真模型：`lenstrans_test_llama.exe`（慢，需 GGUF）。

```
.\build\Release\lenstrans_test_llama.exe --quality-10
powershell -File tools\eval\wgc-probe.ps1 -TimeoutSec 8
```

质量 10 句写入 `tools/eval/out/quality-10.md`（非正式 W1）。WGC 探测写入 `tools/eval/out/wgc-probe.md`。
