# LensTrans

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語** · [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?logo=windows&logoColor=white)](#対応環境)
[![macOS](https://img.shields.io/badge/macOS-API%20stubs-lightgrey?logo=apple)](#対応環境)
[![C++](https://img.shields.io/badge/C%2B%2B-20-00599C?logo=cplusplus)](CMakeLists.txt)
[![UI](https://img.shields.io/badge/shell-Win32%20native-informational)](#何をするものか)
[![Engine](https://img.shields.io/badge/local-Qwen2.5--0.5B%20GGUF-orange)](#機能)

**Windows ネイティブのリアルタイム画面翻訳。** 任意のウィンドウの上に、レイヤードでクリック透過できる枠を置きます。Windows Graphics Capture（WGC）で画素を取り込み、システムの OCR で読み、ローカルの Qwen2.5-0.5B、または自分で書いた OpenAI 互換エンドポイントで訳し、没入塗りかステッカーで原文を覆います。Electron も Tauri も WebView シェルも使いません。

## 何をするものか

画面上の文字はピクセルであって、DOM ではありません。LensTrans はフックを仕込みませんし、他プロセスの私有メモリも読みません。自分の枠の中だけを撮り、文字を認識し、同じ矩形の上に訳を描きます。

```
  ┌─ 対象ウィンドウ ─────────────────────────────────────┐
  │  File   Edit   View                                  │
  │                                                      │
  │    ┌─ LensTrans 枠（Watching、クリック透過）──────┐  │
  │    │                                              │  │
  │    │   Settings          →    设置                │  │
  │    │   Cancel            →    取消                │  │
  │    │   Please wait…      →    请稍等              │  │
  │    │                                              │  │
  │    └──────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────┘
         トレイ  ·  右クリックで開始/停止  ·  左ダブルクリックで表示切替
```

枠は `WS_POPUP` のレイヤード HWND（`WS_EX_LAYERED | TOPMOST | TOOLWINDOW`）で、タスクバーには出しません。**Watching** では `WS_EX_TRANSPARENT` を立て、クリックは下のウィンドウへ抜けます。**Editing** では透過を外し、タイトルバーのドラッグと八方向 12px ハンドルでリサイズできます。複数枠に対応し、枠ごとにステートマシンを持ちます。

```
Hidden → Editing → Watching ⇄ Translating
              Paused ← どの状態からでも（ホットキー。キャプチャは止め、オーバーレイは最後のフレームを残す）
```

表示は二通りだけを正直な実装とします。背景の最頻色で矩形を塗り潰して訳を書く（没入）、あるいは不透明なステッカーで原文を隠す。原文が残ったまま半透明の訳を重ねるのは禁止です。対照モードはステッカーの下に 60% サイズの原文を置くのであって、重ね打ちではありません。字色が塗りに対して WCAG AA 4.5:1 を下回るときは、字色を塗りの反転色に切り替えます。

リポジトリに製品スクリーンショットはありません。上は構造の図示で、存在しない画像 URL を貼らないためです。

よくある画面翻訳は「ビットマップを撮って、別ウィンドウに結果を出す」方式です。LensTrans は **枠をピン留めし、画素の変化に追従し、原文を覆う** 側です。

| | よくあるポップアップ型 | LensTrans |
| --- | --- | --- |
| 位置 | 原文から離れた別窓 | 自分で描いた画素に枠が貼り付く |
| タイミング | ホットキーで一枚切り | 枠内が変われば更新 |
| オフライン | ネット前提が多い | 既定はローカル Qwen2.5-0.5B |
| 見た目 | 原文と訳が同時に見える | 没入塗りまたはステッカーで原文を **覆う** |

## 機能

| 領域 | Windows 上で実際に動くもの |
| --- | --- |
| オーバーレイ | 複数枠、最前面、編集 / クリック透過、トレイ一式 |
| キャプチャ | WGC（ウィンドウセッション / モニタ切り出し）。失敗時は GDI `BitBlt` / `PrintWindow` |
| フレーム差 | 1/4 ダウンサンプル + 8×8 SSD。DIFF なし約 2 秒で休眠し、空転で CPU を食わない |
| OCR | `Windows.Media.OCR` を STA スレッドで実行 → 共通 `OcrBlock`（テキスト、bbox、サンプリング色） |
| 安定化 | bbox+text が一致する連続 2 フレームに、300 ms デバウンスを足してから翻訳へ渡す |
| 表示 | 没入置換 / ステッカー（既定は約 92% 不透明）/ ステッカー+対照。半透明の重ね書きは禁止 |
| ローカル翻訳 | Qwen2.5-0.5B Instruct Q4_K_M、[llama.cpp](https://github.com/ggml-org/llama.cpp) **b10688**（プロセス内リンクまたは `llama-cli`） |
| クラウド翻訳 | WinHTTP `POST {base}/chat/completions`。Base URL / Model / API Key は **すべて空**。空なら無効 |
| 鍵 | DPAPI でディスクへ。設定のシリアライズに `api_key` を出さない（単体テストあり） |
| UI | 設定 5 タブ、初回 3 ステップ案内（案内中は WGC を起こさない） |
| マウス | 右クリックで開始/停止 · 左ダブルクリックで置換/対訳 · 内側ドラッグで移動 · 端ドラッグでサイズ変更 |

## クイックスタート

環境: Windows 10 21H2+ または Windows 11、x64、Visual Studio 2022、Windows 10/11 SDK。

1. 本リポジトリを clone。[ビルド](#ビルド) に従い llama.cpp **b10688** を取り、[models/README.md](models/README.md) に従い GGUF を置く。
2. `lenstrans_overlay` をビルドし、`build\Release\lenstrans_overlay.exe` を実行する。
3. 画面収録の許可が出たら許可する。翻訳対象の文字に枠を置き、枠内を右クリックして開始する。
4. クラウドを使う場合は設定を開き、**自分の** Base URL・モデル名・Key だけを書く。ソースにゲートウェイは同梱しない。

スクリプトによる zip（Inno / NSIS / ストア署名パッケージではない）は [docs/installer.md](docs/installer.md)。本ツリーに本番署名済み MSIX はありません。

## ビルド

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

オーバーレイ内のローカルエンジンには、プロセス内の llama.cpp が必要です。

```bat
git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git third_party\llama.cpp
```

llama.cpp を **Release x64** でビルドしてから LensTrans を再構成します。CMake は `third_party/llama.cpp/build/src/Release/llama.lib` を見つけると `LENSTRANS_WITH_LLAMA=ON` を立てます。ピン留めの詳細は [third_party/README.md](third_party/README.md)。

```
tag:    b10688
commit: c589f0ed10c643678c4707dd160c21ac7633ebc0
remote: https://github.com/ggml-org/llama.cpp.git
```

Ninja + MSVC でも構いません。vcpkg を足さないでください。UI をクロスプラットフォームのシェルに差し替えないでください。

### テスト

| ターゲット | 役割 |
| --- | --- |
| `lenstrans_test` | コア: キャッシュ、ルータ、表示、設定。注入フレームの全経路（WGC なし） |
| `lenstrans_test_hotkey` | 既定の四キー `RegisterHotKey` |
| `lenstrans_test_llama` | 任意。GGUF が必要（`--quality-10` / `--quality-30` / `--flores50`） |
| `lenstrans_e2e_target` | overlay スクリプト用の独立 HWND（白地 `HELLO Settings`） |
| `lenstrans_wgc_probe` | WGC 権限 + OCR スモーク |

`tools/eval/*.ps1` は受け入れ用スクリプトで、報告は `tools/eval/out/` に書き（gitignore 済み）、説明は [tests/README.md](tests/README.md) にあります。

### パッケージ

```bat
powershell -File tools\pack\pack-windows.ps1
powershell -File tools\pack\pack-windows.ps1 -Offline
powershell -File tools\pack\install-windows.ps1
```

基本パックに GGUF は入りません。オフラインパックは基本パック + `models/*.gguf`。上限を超えるとスクリプトは失敗します。インストール先の既定は `%LOCALAPPDATA%\LensTrans\app`。鍵は書きません。GGUF をコピーするのはオフラインパックを作ったときだけです。

## サイズとメモリ（確定した予算）

製品の拘束条件であって、キャッチコピーではありません。受け入れは **Working Set（WS）** で見ます。Private Bytes を「ピークメモリ」として報告しません。

| 項目 | 上限 | 説明 |
| --- | --- | --- |
| 基本パック | **≤ 30 MB** | overlay + llama/ggml DLL。**GGUF なし** |
| 完全オフライン | **≤ 520 MB** | 基本 + 公式 Q4_K_M（約 491 MB）+ インストーラ余白 |
| 推論ピーク | **WS ≤ 550 MB** | GGUF のファイルマップを含む |
| ローカル常駐 | ≤ 600 MB（典型は約 520 MB） | Q4_K_M をロックしたあとの物理的な帰結 |
| 主プロセス（重みなし） | ≤ 80 MB | ウェイト未ロード |
| クラウド常駐 | ≤ 120 MB | クラウドエンジンのみ |
| ≤100 文字ブロックの初トークン | ≤ 800 ms | 現代的な CPU、ウォーム、greedy。対外 SLO ではない |

手元ではスクリプト基本ツリーが約 **4.5 MB**（zip 約 1.8 MB）、オフライン合計約 **496 MB** で、いずれも上限内でした。単機の成果物です。ツールチェーンで数字は変わりますが、予算は変わりません。

既定の重み: `qwen2.5-0.5b-instruct-q4_k_m.gguf`、491400032 バイト、SHA256 `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`。入手手順は [models/README.md](models/README.md)。これを選んだ理由は **Apache-2.0 が EU/UK/KR を含む再配布を許す** からであって、0.5B が専任の機械翻訳に達しているからではありません。

## プライバシー

- **既定はローカル。** 画素はこのマシンから出ません。OCR はシステムのエンジン、翻訳は手元の llama.cpp と自分で置いた GGUF です。
- **クラウドのゲートウェイは空。** ソースに既定の Base URL、サンプル Key、内蔵中継はありません。三項目が揃うまでクラウドは無効です。別に「接続テスト」があります。
- API Key は **DPAPI** だけ。平文の設定ファイルには入りません。
- キャプチャはシステム API だけです。注入はせず、他プロセスの私有メモリも読みません。
- git が止めるもの: `*.gguf`、`*.pfx`、`dist/*.cer`、`third_party/llama.cpp` 一式、`build/`、`.cache/`、`.env`、鍵類。push しないでください。

## 対応環境

| | 状態 |
| --- | --- |
| **Windows 10/11 x64** | C++20 + Win32。これが製品本体です。 |
| **macOS** | `mac/` は Swift AppKit の **インターフェーススタブ**。[mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md) を見てください。ScreenCaptureKit / Vision / Metal は未配線。本リポジトリに Xcode プロジェクトはありません。Windows を先に仕上げます。 |

## 制限（先に読んでください）

- 既定のローカルモデルは **0.5B** です。短い UI 文はしばしば使えます。長文や慣用句は直訳や語順崩れになりがちです。容量の限界であって、「プロンプトをいじれば専任 MT になる」話ではありません。正式な FLORES / COMET 受け入れはまだ開いています。
- 本リポジトリに本番 / ストアのコード署名はありません。`tools/pack/pack-msix.ps1` の test-sign は手元だけ。証明書は入れません。
- macOS は配布物ではありません。
- Hunyuan / HY-MT のコミュニティライセンスは EU/UK/KR を除外します。**既定エンジンにはしません**し、インストーラにも入れません。

## ディレクトリ

```
core/           共有 C++: OcrBlock、フレーム差、ローカル/クラウドエンジン、表示、パイプライン、設定
win/            overlay、WGC キャプチャ、WinRT OCR、トレイと設定、DPAPI
mac/            Swift スタブ（Windows 上ではコンパイルしない）
tests/          単体、e2e フィクスチャ、WGC プローブ
tools/pack/     zip / MSIX スクリプト
tools/eval/     プローブと品質スクリプト（out/ はリポジトリに入れない）
docs/           インストーラ説明と M0 文書
models/         GGUF を置く（重みはリポジトリに入れない）
third_party/    llama.cpp b10688 を自分で clone（ツリーはリポジトリに入れない）
```

モジュール表と厳しい制約: [docs/M0-poc-structure.md](docs/M0-poc-structure.md)。モデル許諾と評価計画: [docs/M0-model-eval.md](docs/M0-model-eval.md)。

## ライセンス

[MIT](LICENSE) © 2026 flynn (suifei)。

任意の Qwen2.5-0.5B GGUF は **Apache-2.0**（Alibaba Cloud）です。重みを再配布するときはその許諾を添えてください。照合用コピー: `tools/eval/licenses/`。llama.cpp は上流のライセンスに従います。公式リポジトリから clone してください。

## 貢献

「ネイティブ Windows の画面翻訳」に沿った issue と PR を歓迎します。

- UI は Win32 / AppKit のまま。Electron、Tauri、Qt、Flutter、WebView をシェルにしないでください。
- 既定のクラウドホスト、サンプル API Key、ゲートウェイ定数を足さないでください。
- `*.gguf`、`*.pfx`、`dist/*.cer`、`third_party/llama.cpp`、`build/`、`.cache/`、秘密情報をコミットしないでください。
- 表示経路で「原文がまだ見えるのに半透明の訳が重なる」状態は回帰です。
- `core/` を触ったら先に `lenstrans_test` を通してください。

評価の途中で llama.cpp の commit を上げないでください。ロックは [third_party/README.md](third_party/README.md)。
