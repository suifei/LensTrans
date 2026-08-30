# M0 模型评测方案（2 周）

对齐 PRD v0.2 §6.1 / §7。本文件是可执行计划。评测仍要跑速度 / 内存 / COMET，但**产品默认引擎已锁，不再用评测结果改默认模型**。

已拍板产品决策（评测不得改写）：

1. **分发双轨**：基础安装包 ≤30MB；首次引导默认勾选「下载本地模型」（断点续传 + SHA256）。另提供含模型完整离线包 **≤520MB**（2026-08-30 书面上调：官方 Qwen2.5-0.5B Instruct Q4_K_M 约 491MB，首启下载不变，余量给安装器）。默认路径是首启下载，完整包是并列渠道，不是二选一产品形态。
2. **云端不预填公共网关**：Base URL / API Key / Model 全部留空，只留配置区 +「测试连接」。
3. **目标市场包含 EU / UK / KR**。
4. **Hunyuan / HY-MT 社区许可 → 硬出局**。不得作为默认引擎，也不得作为候选主模型。
5. **本地默认引擎锁定：Qwen2.5-0.5B Instruct，int4 / Q4 GGUF，Apache-2.0。** 选定原因是许可可覆盖 EU/UK/KR 再分发，**不是**翻译质量已经测完。
6. Hy-MT2 1.8B 等专职翻译档：仅可作质量对照实验，**不得进默认包**，且不得突破离线包 **≤520MB**（除非用户以后书面再改上限）。
7. **推理峰值 Working Set ≤550MB**（2026-08-30 书面上调，对齐已锁 Qwen2.5-0.5B Instruct Q4_K_M）。**不再压量化。** 这是许可锁定该官方 GGUF 后的物理后果，不是评测偷降标准。

本地引擎硬门槛（默认引擎 C 必须过；过不了是集成问题，不是换回 Hunyuan 的理由）：

| 项 | 门槛 |
| --- | --- |
| 推理峰值内存 | **进程 Working Set ≤550MB**（含权重 mmap）。验收只看 WS，不看 Private Bytes |
| 本地模式常驻总量 | ≤600MB；典型约 520MB（与 550MB 峰值兼容；取代原 ≤450MB / 典型 320MB） |
| 主进程不含模型 | ≤80MB（未改） |
| 云端常驻总量 | ≤120MB（未改） |
| ≤100 字块首字 | ≤ 800ms（现代 CPU，热启动，贪心；未改） |
| GGUF 体积 | 离线包 **≤520MB**（模型约 491MB + 安装器余量）。基础包仍 ≤30MB。十进制 520×10⁶ − 491400032 ≈ 28.6MB 给安装器，打包须压进该余量 |
| 运行时 | 官方 `llama.cpp` 主线可加载；禁止捆绑 Electron/Tauri |
| 许可 | 必须允许本产品商用 + 随安装包再分发到 **含 EU/UK/KR** 的目标市场 |

**体积（已核实）：** 官方 `qwen2.5-0.5b-instruct-q4_k_m.gguf` 为 **491400032 字节（约 468.6 MiB / 491 MB）**，SHA256 `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`。2026-08-30 书面将完整离线包上限改为 **≤520MB**，使该文件可进完整包；首启按需下载路径不变。基础包仍 ≤30MB、不含 GGUF。Hy-MT 1.8B 对照仍不得进默认包。

**内存测量定义（验收）：**

- **推理峰值** = 推理进程的 **Working Set**（Windows `PROCESS_MEMORY_COUNTERS_EX.WorkingSetSize` / PowerShell `WorkingSet64`）。含 GGUF 文件映射。llama.cpp 日志里的 Host 总量作对照，**不以 Host 替代 WS**。
- **Private Bytes**（`PrivateMemorySize64`）只记附录，**不参与通过/淘汰**。不得与 WS 混报成「峰值内存」。
- 本机冒烟（Host 511 MiB / WS ~488 MiB）相对 550MB 线已过，**不是 W1 正式验收**。

## 1. 候选表（2026-08-30 标死）

| ID | 角色 | 状态 | 权重 | 量化 | 标称/实测体积 | 许可 | 说明 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **C** | **默认定版方向** | **锁定** | 官方 `Qwen/Qwen2.5-0.5B-Instruct-GGUF` → `qwen2.5-0.5b-instruct-q4_k_m.gguf` | Q4_K_M | 491400032 B | **Apache-2.0**，可全球商用再分发 | 评测主对象。交付只认官方 GGUF 或用锁定 llama.cpp 自行 convert |
| **A** | 原 Hunyuan-0.5B | **许可硬出局** | — | — | — | Hunyuan Community：排除 EU/UK/KR | 不再下载、不再测、不进包 |
| **B** | Hy-MT2-1.8B-1.25bit | 仅质量对照实验 | 官方约 440MB | 1.25-bit STQ | ~440MB | HY Community：排除 EU/UK/KR | 许可已出局。M0 **默认不下载**。不得打进默认/离线包 |
| **D** | HY-MT1.5-1.8B Q4 | 仅质量对照实验 | 1.13GB | Q4_K_M | 1.13GB | 同上 | 体积+许可双杀。M0 **默认不下载** |

不纳入：

- `facebook/nllb-200-distilled-600M`：CC-BY-NC
- OPUS-MT：Marian，不是 GGUF 核
- Qwen3-0.6B Q4（~484MB）：未锁定，不跑

## 2. 许可结论（C，已读官方 LICENSE）

核对时间：2026-08-30。全文副本：`tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt`。源头：`https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/raw/main/LICENSE`（Copyright 2024 Alibaba Cloud，Apache-2.0）。

| 项 | 结论 |
| --- | --- |
| SPDX | Apache-2.0 |
| 商用 | 允许 |
| 随闭源安装包再分发权重 | 允许（须附协议副本，保留版权/NOTICE） |
| 地域 | **无** EU/UK/KR 排除 |
| MAU / 营收门槛 | 无 |
| 商标 | 不授予 Qwen / Alibaba 商标权；关于页可做来源说明 |

Hunyuan / HY-MT：目标市场含 EU/UK/KR → **硬出局**。不再写「有条件通过」。

选 C 的产品理由：**Apache-2.0 能覆盖 EU/UK/KR 再分发**。质量（BLEU/COMET/屏幕域）仍是 M0 必须补的验收，不是选型依据。

## 3. llama.cpp 锁定（D1 已写死）

```
tag:    b10688
commit: c589f0ed10c643678c4707dd160c21ac7633ebc0
remote: https://github.com/ggml-org/llama.cpp.git
```

落盘：`tools/eval/out/LOCK.txt`。禁止评测中途升级。本仓库尚未 submodule 克隆；需要编译 `llama-cli` 时：

```
git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
```

线程数 = 物理核（W1 用 6）。`-c 1024 --batch-size 512 --temp 0`，`--n-gpu-layers 0`。质量档 beam=2 只在 C 上补一组。

## 4. 硬件基线

| 机 | 用途 | 规格 |
| --- | --- | --- |
| **W1 必测** | 验收数字 | Win11 24H2 x64，6C12T 级，16GB RAM，核显，CPU only |
| **W2 抽测** | 老机器 | Win10 21H2 x64，4C 级，8GB RAM |
| **M1 可选** | 不挡 M0 | macOS 12.3+ Apple Silicon |

权重与缓存只许落 **D: 项目盘**，禁止 `C:\Users\<user>\.cache`：

```
$env:HF_HOME = "D:\works\LensTrans\.cache\hf"
$env:HF_HUB_CACHE = "D:\works\LensTrans\.cache\hf\hub"
$env:MODELSCOPE_CACHE = "D:\works\LensTrans\.cache\modelscope"
```

GGUF 目标路径：`D:\works\LensTrans\models\qwen2.5-0.5b-instruct-q4_k_m.gguf`（已 gitignore）。

## 5. 下载（D2）

优先 ModelScope，失败再 Hugging Face。官方文件名与 SHA256 以 HF API 为准。

```
curl.exe -L -C - --retry 8 --retry-all-errors -o D:\works\LensTrans\models\qwen2.5-0.5b-instruct-q4_k_m.gguf "https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf"
```

备选：

```
curl.exe -L -C - --retry 8 --retry-all-errors -o D:\works\LensTrans\models\qwen2.5-0.5b-instruct-q4_k_m.gguf "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
```

完成后必须：

```
Get-FileHash -Algorithm SHA256 D:\works\LensTrans\models\qwen2.5-0.5b-instruct-q4_k_m.gguf
(Get-Item D:\works\LensTrans\models\qwen2.5-0.5b-instruct-q4_k_m.gguf).Length
```

期望：Length = `491400032`，SHA256 = `74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB`（大小写不敏感）。不一致则删文件重下，禁止用错文件评测。

进度见 `tools/eval/out/download-status.md`（2026-08-30：**已下完**，SHA256 已核对）。

冒烟（有 `llama-cli` 之后）：

```
llama-cli -m D:\works\LensTrans\models\qwen2.5-0.5b-instruct-q4_k_m.gguf -p "ping" -n 8 -c 1024 -ngl 0 --temp 0
```

## 6. 数据集与测法（只跑 C）

| 集 | 用途 | 规模 |
| --- | --- | --- |
| FLORES-200 devtest | 主质量 | `eng-zho` `zho-eng` `jpn-zho` `zho-jpn` `kor-zho` `zho-kor`，每向 200 句 |
| 屏幕域 | 产品分布 | `tools/eval/data/screen.jsonl`：150 UI + 50 短段落（≤100 字） |
| 术语一致 | 附录 | 20 组，不单独淘汰 |

- BLEU：`sacrebleu` 13a
- COMET：`Unbabel/wmt22-comet-da`，报告 mean 与 95% CI
- 屏幕域无参考译文时不做假 BLEU，用人工 3 档

速度：热启动丢 3 条，再测屏幕域 ≤100 字 30 条。W1 首字 P95 >800ms → C 记「速度未达」，**不换 Hunyuan、不压量化**。内存：W1 推理进程 **Working Set** 峰值 >550MB → 记未达。Private Bytes 只附录。B/D 对照若将来要跑，必须另机另目录，且不得写入 `models/` 默认文件名，不得进默认包。

翻译 prompt（C 固定，禁止为刷分改写；M1 再搜）：

```
Translate the following segment into {target_language}, without additional explanation.

{source}
```

中文目标语言用：`将以下文本翻译为{target_language}，注意只需要输出翻译后的结果，不要额外解释：`

输出只保留译文。剥 `<think>`、`Sure,`、包裹引号。空输出计 0。

## 7. 日程（按锁定后的范围）

| 日 | 产出 |
| --- | --- |
| D1 | llama.cpp 锁定；C 的 LICENSE 结论。**已完成** |
| D2 | 下完 C 的官方 Q4_K_M；SHA256 核对。**已完成** |
| D3 | `llama-cli` 冒烟 **已完成**（见下节）。FLORES 100 句地板仍待做 |
| D4–D5 | W1 速度 + 内存（仅 C） |
| D6–D7 | FLORES 六向 BLEU |
| D8–D9 | COMET + 屏幕域人工评 |
| D10 | 填写决策表（C 为默认；记录是否达硬门槛与体积冲突） |
| D11 | W2 抽测；beam=2 一组 |
| D12 | 冻结 SHA256、prompt、LOCK commit。离线包上限已书面改为 ≤520MB |

## 8. 定版决策表

复制到 `tools/eval/out/DECISION.md`：

| 项 | C Qwen2.5-0.5B Q4_K_M（默认） | A Hunyuan | B/D HY-MT |
| --- | --- | --- | --- |
| 产品角色 | 锁定默认 | 禁止 | 禁止进包 |
| 许可（EU/UK/KR） | Apache-2.0 通过 | 硬出局 | 硬出局 |
| llama.cpp | b10688 | — | — |
| GGUF 字节 / SHA256 | 491400032 / 74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB（已复核） | — | — |
| 峰值 Working Set | 本机冒烟 487.6 MiB（Host 511 MiB；非正式 W1）。新线 ≤550MB：**冒烟已过** | — | — |
| 峰值 Private Bytes（附录） | 冒烟 183.4 MiB，不参与验收 | — | — |
| 首字 P50/P95 | 冒烟热态约 93ms（单条，非正式 W1） | — | — |
| FLORES en↔zh COMET | （待测） | — | — |
| 进默认包 | 是（身份已锁） | 否 | 否 |
| 进 ≤520MB 离线包 | **可以**（491MB 模型 + 安装器余量） | 否 | 否 |

回滚：C 速度/内存/质量未达时，48h 内只允许（1）改 prompt / 线程（仍用已锁官方 Q4_K_M，**不得再压量化**），或（2）停本地默认、只走空配置云端。**禁止回滚到 Hunyuan。** 不保留双模型热切换。

## 9. 双轨分发

- 基础包 ≤30MB：无 GGUF。
- 首启：默认勾选下载上述官方文件；Range 续传；先 SHA256 再改名。失败不阻塞「仅云端」（云端仍空）。
- 离线包 **≤520MB**（书面上调）：打进同一官方 Q4_K_M + 运行时/安装器。首启下载仍是默认路径。十进制余量约 28.6MB，安装器须挤进该余量（基础包目标仍 ≤30MB，完整包里的安装器部分按余量裁）。

## 10. D3 冒烟结果（2026-08-30，本机）

完整记录：`tools/eval/out/smoke.md`。复现脚本：`tools/eval/smoke-qwen.ps1`。

- **能加载。** `llama-cli` 路径：`third_party/llama.cpp/build/bin/Release/llama-cli.exe`（b10688 / c589f0e）。
- 样例英→中：`It's on the house.` → `它在房子里。`（字面，未译成语；只证明能出中文）。
- 热态：prompt eval 80.84ms / 25 tok，decode 11.97ms/tok，首字约 **93ms** → **过 800ms**。冷启动墙钟约 1.4s（含 load），不拿来比 800ms。
- 内存：llama Host **511 MiB**（权重 462 + ctx 12 + compute 36）；进程 **WS 487.6 MiB**；Private 183.4 MiB（附录）。按已拍板 **WS ≤550MB：本机冒烟已过**。不是 W1 正式验收。
- 本机为 Intel Family 6 Model 170、22 线程，**不是** W1 规格机。
- 离线包 ≤520MB：模型 491MB 可进完整包。常驻总量按新线 ≤600MB / 典型约 520MB。

## 11. 不做

- 不下载 A/B/D
- 不微调/蒸馏
- 不把 DirectML/Metal 当 Windows CPU 验收
- 不预置云端 Base URL
- 不把 NLLB/OPUS/Hunyuan 塞进安装包
- 不引入 Electron/Tauri
