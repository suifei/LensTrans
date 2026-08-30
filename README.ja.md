# LensTrans

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語** · [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?logo=windows&logoColor=white)](#macos)
[![macOS](https://img.shields.io/badge/macOS-stubs-lightgrey?logo=apple)](#macos)
[![C++](https://img.shields.io/badge/C%2B%2B-20-00599C?logo=cplusplus)](CMakeLists.txt)
[![Engine](https://img.shields.io/badge/local-Qwen2.5--0.5B%20GGUF-orange)](#機能)

Windows 向けのネイティブなリアルタイム画面翻訳です。画面上にクリック透過の枠を置き、Windows Graphics Capture（WGC）で画素を取り、システム OCR で読み、ローカル Qwen2.5-0.5B または自分で設定した OpenAI 互換エンドポイントで訳し、没入塗りまたはステッカーで原文を覆います。別ウィンドウに結果を出す方式ではありません。Electron / Tauri は使いません。

## ポップアップ型との違い

多くの画面翻訳は画像を切り出して結果ウィンドウを開きます。LensTrans は **領域指定・常時・その場で覆う** 方式です。

| | ポップアップ型 | LensTrans |
| --- | --- | --- |
| 位置 | 原文から離れた別窓 | 選んだ領域に固定した透明枠 |
| タイミング | ホットキーで一枚 | 枠内の画素が変われば訳す |
| オフライン | 多くは通信前提 | 既定はローカル Qwen2.5-0.5B |
| 見え方 | 原文と訳が同時に見える | **塗りつぶし（immersive）か帯（sticker）で原文を隠す。重ね書き禁止** |

半透明の訳を原文の上に載せません。背景を塗ってから訳を書くか、不透明な帯で原文を隠します。対照表示は原文を小さくしコントラストを確保するのであって、二行を重ねません。

## 画面（リポジトリに製品スクショはありません）

git には製品スクリーンショットを入れていません。実行時のイメージは次のとおりです。

```
  ┌─ ブラウザ / ゲーム / PDF ─────────────────────────────┐
  │                                                       │
  │    ┌ LensTrans 枠 ─────────────────────────────────┐  │
  │    │ ████ 原文を覆う塗り                             │  │
  │    │ お待ちください                                  │  │
  │    │ （immersive または sticker。文字は重ねない）      │  │
  │    └───────────────────────────────────────────────┘  │
  │                                                       │
  └───────────────────────────────────────────────────────┘
       Watching 中は下の窓へクリック透過    Ctrl+E で枠を編集
```

実物は `build\Release\lenstrans_overlay.exe` をビルドして確認してください。

## 機能

- **複数枠:** `Ctrl+Shift+L` で領域を追加。枠ごとにキャプチャ / OCR / 翻訳。
- **キャプチャ:** `Windows.Graphics.Capture`。失敗時は GDI `BitBlt` / `PrintWindow`。フレーム差分（1/4 + 8×8 SSD）。静止後はスリープ。
- **OCR:** `Windows.Media.OCR` → 共通 `OcrBlock`。2 フレーム安定 + 300 ms デバウンス。
- **翻訳:** ローカル **Qwen2.5-0.5B Instruct Q4_K_M**（Apache-2.0）。任意で OpenAI 互換クラウド。
- **描画:** immersive / sticker / 対照。塗りに対するコントラストが不足すれば文字色を反転。
- **トレイと設定:** トレイ一式、設定 5 タブ、初回 3 ステップ案内。
- **秘密情報:** クラウド API キーは DPAPI。平文の設定ファイルには書きません。

対象市場に **EU / UK / KR** を含みます。ローカル既定は再配布可能な Qwen（Apache-2.0）です。これらの地域を除外するコミュニティライセンスのモデルは使いません。

## インストール

このリポジトリは**ソース**です。配布は二系統で、どちらか一方の製品ではありません。

| パッケージ | 内容 | 上限 |
| --- | --- | --- |
| **基本** | ランタイム（exe + llama/ggml DLL）。**GGUF なし** | **≤30 MB** |
| **完全オフライン** | 基本 + 同じ公式 Q4_K_M | **≤520 MB**（重み約 491 MB、残りはインストーラ） |

実行時ピークは **Working Set ≤550 MB**（マップした重みを含む。Private Bytes では判定しない）。

- ネットワークが無い場合は完全オフラインパック。
- オンライン時の製品方針: 基本パックのあと、初回案内でローカルモデルの利用/取得が既定（レジューム + SHA-256 検証後に確定）。この git リポジトリは約 491 MB の GGUF を**置きません**。
- ソースから実行する場合: 公式ファイルを `models\qwen2.5-0.5b-instruct-q4_k_m.gguf` に置く。手順は [models/README.md](models/README.md)。

梱包（先に Release ビルド）:

```powershell
powershell -File tools/pack/pack-windows.ps1
powershell -File tools/pack/pack-windows.ps1 -Offline
powershell -File tools/pack/install-windows.ps1
```

サイズ検査は [docs/installer.md](docs/installer.md)。VC++ / Universal CRT はシステム依存とし、基本パックには入れません。

## ソースからのビルド（Windows）

**Visual Studio 2022**、Windows 10 SDK、CMake ≥ 3.24、x64。

1. [third_party/README.md](third_party/README.md) に従い `llama.cpp` **b10688** を取得してビルドする。このリポジトリはそのツリーもビルド成果も含みません。
2. 上記の公式 GGUF を置く。または先に llama 非リンクでテストだけビルドする。

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

プロセス内ローカルエンジン: 事前ビルドの `llama.lib` があれば CMake が `LENSTRANS_WITH_LLAMA` を有効にします。ライブラリが無いのに無理にオンにしないでください。

画面収録の許可を求められたら許可してください。Watching のキャプチャは WGC です。案内ウィンドウは探査のためにキャプチャセッションを**開始しません**。

## ホットキー

| キー | 動作 |
| --- | --- |
| `Ctrl+E` | 枠の編集 / クリック透過（Watching 中は下の窓がヒット） |
| `Ctrl+Shift+L` | 翻訳枠を追加 |
| `Ctrl+T` | 一時停止 / 再開 |
| `Ctrl+Shift+H` | 全枠の表示 / 非表示 |
| `Ctrl+,` | 設定 |
| `Esc` | 終了 |

トレイも同じ操作です。キーは設定で変更できます。

## プライバシー

- **既定はオフライン。** ローカルエンジンは画面上の文字を第三者へ送りません。
- **クラウドのゲートウェイは空。** Base URL / API キー / Model は未入力が初期値です。ソースに公開中継 URL はありません。「接続テスト」だけ用意しています。
- キーは DPAPI。`.env`、証明書、pfx は git に入りません。
- キャプチャは自分で描いた枠の中だけです。

## License

[MIT](LICENSE) © 2026 flynn (suifei)。既定のローカル重み Qwen2.5-0.5B Instruct は **Apache-2.0**（Alibaba Cloud）。`llama.cpp` は上流のライセンスに従います。

## macOS

**同等実装ではありません。** `mac/` は Swift のインターフェース骨格です。Windows 上ではビルドせず、完成アプリでもありません。[mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md) を見てください。

## 貢献

Win32 / AppKit を維持してください。Electron / Tauri を入れない。クラウドの既定ホストや Key を追加しない。`*.gguf` / `*.pfx` / `third_party/llama.cpp` / `build/` をコミットしない。`core/` を触る前に `lenstrans_test` を通す。
