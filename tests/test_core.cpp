#include "lenstrans/autostart.hpp"
#include "lenstrans/batch_translation.hpp"
#include "lenstrans/boxes.hpp"
#include "lenstrans/cache.hpp"
#include "lenstrans/cloud_http.hpp"
#include "lenstrans/geom.hpp"
#include "lenstrans/dispatch.hpp"
#include "lenstrans/engine.hpp"
#include "lenstrans/frame_diff.hpp"
#include "lenstrans/model_meta.hpp"
#include "lenstrans/paths.hpp"
#include "lenstrans/pipeline.hpp"
#include "lenstrans/present.hpp"
#include "lenstrans/router.hpp"
#include "lenstrans/settings.hpp"
#include "lenstrans/sha1.hpp"
#include "lenstrans/ui_state.hpp"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

using namespace lenstrans;

static int g_fail = 0;

#define CHECK(cond)                                                               \
  do {                                                                            \
    if (!(cond)) {                                                                \
      std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);        \
      ++g_fail;                                                                   \
    }                                                                             \
  } while (0)

static void FillSolid(std::vector<std::uint8_t>& img, int w, int h, int b, int g, int r) {
  img.assign(static_cast<std::size_t>(w) * h * 4, 0);
  for (int i = 0; i < w * h; ++i) {
    img[static_cast<std::size_t>(i) * 4 + 0] = static_cast<std::uint8_t>(b);
    img[static_cast<std::size_t>(i) * 4 + 1] = static_cast<std::uint8_t>(g);
    img[static_cast<std::size_t>(i) * 4 + 2] = static_cast<std::uint8_t>(r);
    img[static_cast<std::size_t>(i) * 4 + 3] = 255;
  }
}

struct TestCapture final : ICaptureProvider {
  int calls = 0;
  bool Capture(CapturedFrame& frame, const CancellationToken&) override {
    ++calls;
    frame.width = 320;
    frame.height = 180;
    frame.stride_bytes = frame.width * 4;
    frame.sequence = static_cast<std::uint64_t>(calls);
    frame.bgra.assign(static_cast<std::size_t>(frame.stride_bytes) * frame.height, 255);
    return true;
  }
};

struct TestOcr final : IOcrProvider {
  int calls = 0;
  bool Recognize(const CapturedFrame&, const CancellationToken&, std::vector<OcrBlock>& blocks) override {
    ++calls;
    blocks = {
        {"Hello", {10, 12, 40, 20}, 20, {0, 0, 0}, {255, 255, 255}, 2},
        {"world", {58, 12, 40, 20}, 20, {0, 0, 0}, {255, 255, 255}, 2},
        {"Second line", {10, 64, 110, 20}, 20, {0, 0, 0}, {240, 240, 240}, 40},
    };
    return true;
  }
};

struct TestPresenter final : IPresentationSink {
  int calls = 0;
  PresentationFrame last;
  bool Present(const PresentationFrame& frame, const CancellationToken&) override {
    ++calls;
    last = frame;
    return true;
  }
};

int main() {
  {
    std::vector<OcrBlock> blocks = {
        {"Hello", {10, 20, 80, 18}, 18, {}, {}, 1},
        {"world", {10, 42, 90, 18}, 18, {}, {}, 1},
    };
    const auto source = BuildBatchSource(blocks);
    CHECK(source.find("0|||Hello") != std::string::npos);
    const auto prompt = BuildBatchUserPrompt(
        source, "its automatically detected source language", "Simplified Chinese");
    CHECK(prompt.find("不要合并、拆分、省略") != std::string::npos);
    CHECK(BuildTranslatePrompt({.text = "你好", .src_lang = "zh", .tgt_lang = "en"})
              .find("from Simplified Chinese into English") != std::string::npos);
    const auto parsed = ParseBatchTranslation(
        "0|||你好\n1|||世界", 2);
    CHECK(parsed.size() == 2 && parsed[0] == "你好" && parsed[1] == "世界");
    const auto missing = ParseBatchTranslation("[[LT:1]]世界[[/LT:1]]", 2);
    CHECK(missing[0].empty() && missing[1] == "世界");
    const auto bound = BindBatchTranslation(blocks, "[[LT:0]]你好[[/LT:0]]");
    CHECK(bound.size() == 2 && bound[0].source.bbox.x == 10 && bound[0].translation == "你好");
    CHECK(bound[1].source.bbox.y == 42 && bound[1].translation.empty());
    CHECK(BatchTranslationUsable(blocks, "0|||你好\n1|||世界"));
    CHECK(!BatchTranslationUsable(blocks, "0|||Hello\n1|||world"));
    CHECK(TranslationUsableForTarget("Hello", "你好", "zh"));
    CHECK(!TranslationUsableForTarget("Hello", "Hello", "zh"));
    CHECK(!TranslationUsableForTarget("Hello", "Hello again", "zh"));
    CHECK(!TranslationUsableForTarget("Hello", "Résumé", "zh-Hans"));
    CHECK(TranslationUsableForTarget("Hello", "这是 Windows 设置", "Simplified Chinese"));
    CHECK(SourceNeedsTranslationForTarget("Hello LensTrans", "zh"));
    CHECK(!SourceNeedsTranslationForTarget("mac-desktop.txt", "zh"));
    CHECK(!SourceNeedsTranslationForTarget("mac-desktop.txt — Edited", "zh"));
    CHECK(!SourceNeedsTranslationForTarget("→", "zh"));
    CHECK(SourceNeedsTranslationForTarget("こんにちは", "zh"));
    CHECK(SourceNeedsTranslationForTarget("Привет", "zh"));
    CHECK(SourceNeedsTranslationForTarget("مرحبا", "zh"));
    CHECK(TranslationUsableForTarget("你好", "Hello", "en"));
    CHECK(!TranslationUsableForTarget("你好", "世界", "en"));
    CHECK(IsRedundantParagraphTranslation("这是第一句完整译文 这是第二句", "这是第一句完整译文"));
    CHECK(!IsRedundantParagraphTranslation("第一句", "第三句"));
    CHECK(ParseBatchTranslation("protocol missing", 2) == std::vector<std::string>({"", ""}));
    const auto formatted = ParseBatchTranslation(
        "<target><sn>0|||你好</sn><sn>1|||A &amp; B</sn></target>", 2);
    CHECK(formatted.size() == 2 && formatted[0] == "你好" && formatted[1] == "A & B");
    CHECK(BuildHunyuanFormattedBatchSource("0|||A < B\n1|||C & D") ==
          "<source>\n<sn>0|||A &lt; B</sn>\n<sn>1|||C &amp; D</sn>\n</source>");
    const auto ranges = BatchRanges(10, 4);
    CHECK(ranges.size() == 3 && ranges[0].first == 0 && ranges[0].second == 4);
    CHECK(ranges[2].first == 8 && ranges[2].second == 10);
    CHECK(BatchFallbackUsable(5, 3));
    CHECK(!BatchFallbackUsable(5, 2));
    TranslateRequest budget;
    budget.batch_protocol = true;
    budget.text.assign(3000, 'x');
    CHECK(TranslationOutputTokenBudget(budget) == 768);
    budget.quality = true;
    CHECK(TranslationOutputTokenBudget(budget) == 1024);
    TranslateRequest hy_request{.text = "Hello", .src_lang = "auto", .tgt_lang = "zh"};
    const auto hy_prompt = BuildLocalEnginePrompt(hy_request, "HY-MT1.5-1.8B-Q4_K_M.gguf");
    CHECK(hy_prompt.rfind("<|startoftext|>", 0) == 0);
    CHECK(hy_prompt.find("将以下文本翻译为简体中文") != std::string::npos);
    CHECK(hy_prompt.rfind("<|extra_0|>") == hy_prompt.size() - 11);
  }

  {
    UiState ui;
    CHECK(ui.activity == UiActivity::Stopped);
    CHECK(ResolveUiVisual(ui).border.b == 255);
    auto result = ApplyUiInput(ui, UiInput::RightClick);
    CHECK(result.activity_changed && result.state.activity == UiActivity::Active);
    CHECK(ResolveUiVisual(result.state).border.g == 209);
    result = ApplyUiInput(result.state, UiInput::LeftDoubleClick);
    CHECK(result.presentation_changed && result.state.presentation == UiPresentation::Bilingual);
    const auto bilingual = ResolveUiVisual(result.state);
    CHECK(bilingual.border.r == 255 && bilingual.border.g == 159);
    result = ApplyUiInput(result.state, UiInput::RightClick);
    CHECK(result.state.activity == UiActivity::Stopped);
    const auto stopped_bilingual = ResolveUiVisual(result.state);
    CHECK(stopped_bilingual.border.r == 175 && stopped_bilingual.border.b == 222);
    result = ApplyUiInput(result.state, UiInput::Pause);
    CHECK(result.state.activity == UiActivity::Stopped);
    result = ApplyUiInput(ApplyUiInput(result.state, UiInput::Start).state, UiInput::Pause);
    CHECK(result.state.activity == UiActivity::Paused);
    CHECK(ResolveUiVisual(result.state).border.r == 142);
    CHECK(HitTestUiAnchor(2, 2, 480, 320, 12, true) == UiAnchor::NW);
    CHECK(HitTestUiAnchor(240, 160, 480, 320, 12, true) == UiAnchor::Move);
    CHECK(HitTestUiAnchor(240, 160, 480, 320, 12, false) == UiAnchor::Move);
    const UiRect start{100, 100, 480, 320};
    const auto north = ApplyUiDrag(start, UiAnchor::N, 0, -40, 80, 80);
    CHECK(north.y == 60 && north.h == 360 && north.y + north.h == 420);
    const auto south = ApplyUiDrag(start, UiAnchor::S, 0, 40, 80, 80);
    CHECK(south.y == 100 && south.h == 360);
    const auto west_min = ApplyUiDrag(start, UiAnchor::W, 700, 0, 160, 80);
    CHECK(west_min.x == 420 && west_min.w == 160 && west_min.x + west_min.w == 580);
    const auto north_min = ApplyUiDrag(start, UiAnchor::N, 0, 500, 80, 80);
    CHECK(north_min.y == 340 && north_min.h == 80 && north_min.y + north_min.h == 420);
  }

  // SHA-1: "abc" → a9993e364706816aba3e25717850c26c9cd0d89d
  CHECK(Sha1Hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d");
  const PresentationSemantics default_presentation{};
  CHECK(CacheKey("en", "zh", "hello") ==
        CacheKey("en", "zh", "hello", false, default_presentation));
  CHECK(CacheKey("en", "zh", "hello") !=
        CacheKey("en", "zh", "hello", false, default_presentation, "auto", "zh"));
  CHECK(CacheKey("en", "zh", "hello") != CacheKey("zh", "zh", "hello"));
  CHECK(CacheKey("en", "zh", "hello") != CacheKey("en", "en", "hello"));
  CHECK(CacheKey("en", "zh", "hello") != CacheKey("en", "zh", "hello", true));
  CHECK(CacheKey("en", "zh", "a|b") != CacheKey("en", "zh", "a", false, {}, "auto", "zh"));
  {
    PresentationSemantics p = default_presentation;
    p.contrast = true;
    p.sticker_alpha = 80;
    CHECK(CacheKey("en", "zh", "hello", false, p) != CacheKey("en", "zh", "hello"));
    CHECK(CacheKey("en", "zh", "hello", false, {}, "auto", "zh") !=
          CacheKey("en", "zh", "hello", false, {}, "ja", "zh"));
  }

  TranslationCache cache;
  std::string miss;
  CHECK(!cache.Get("k", miss));
  cache.Put(CacheKey("en", "zh", "hi"), "你好");
  std::string hit;
  CHECK(cache.Get(CacheKey("en", "zh", "hi"), hit) && hit == "你好");
  CHECK(cache.Size() == 1);
  cache.Clear();
  CHECK(cache.Size() == 0);

  const int w = 128, h = 128;
  std::vector<std::uint8_t> a, b;
  FillSolid(a, w, h, 10, 10, 10);
  FillSolid(b, w, h, 10, 10, 10);
  auto d0 = DiffFrames(a.data(), b.data(), w, h, w * 4);
  CHECK(d0.changed_count == 0);

  for (int y = 0; y < 32; ++y) {
    for (int x = 0; x < 32; ++x) {
      const int i = (y * w + x) * 4;
      b[static_cast<std::size_t>(i)] = 200;
      b[static_cast<std::size_t>(i) + 1] = 200;
      b[static_cast<std::size_t>(i) + 2] = 200;
    }
  }
  auto d1 = DiffFrames(a.data(), b.data(), w, h, w * 4);
  CHECK(d1.changed_count >= 1);
  CHECK(d1.cols > 0 && d1.rows > 0);

  std::vector<std::uint8_t> mask;
  UnionChangedAndDilated(d1, {}, 1, mask);
  int marked = 0;
  for (auto v : mask) marked += v;
  CHECK(marked >= d1.changed_count);

  CHECK(RouteEngine({EnginePref::Auto, true, 10, true, true}) == EngineKind::Local);
  CHECK(RouteEngine({EnginePref::Auto, false, 10, true, true}) == EngineKind::Local);
  CHECK(RouteEngine({EnginePref::Auto, false, 201, true, true}) == EngineKind::Cloud);
  CHECK(RouteEngine({EnginePref::Auto, false, 201, true, false}) == EngineKind::Local);
  CHECK(RouteEngine({EnginePref::Cloud, false, 10, false, true}) == EngineKind::Cloud);
  CHECK(RouteEngine({EnginePref::Local, false, 500, true, true}) == EngineKind::Local);
  CHECK(RouteEngine({EnginePref::Auto, true, 10, false, true}) == EngineKind::None);

  CHECK(DecidePresent(5.f, false, RenderLock::Auto) == PresentMode::Immersive);
  CHECK(DecidePresent(40.f, false, RenderLock::Auto) == PresentMode::Sticker);
  CHECK(DecidePresent(40.f, true, RenderLock::Auto) == PresentMode::StickerContrast);
  CHECK(DecidePresent(5.f, false, RenderLock::Sticker) == PresentMode::Sticker);
  CHECK(ContrastOk(0, 0, 0, 255, 255, 255));
  CHECK(!ContrastOk(200, 200, 200, 210, 210, 210));
  CHECK(ContrastRatio(255, 255, 255, 0, 0, 0) >= kWcagAaContrast);
  CHECK(ContrastRatio(0, 0, 0, 255, 255, 255) >= kWcagAaContrast);
  CHECK(ContrastRatio(140, 140, 140, 128, 128, 128) < kWcagAaContrast);
  {
    OcrBlock first{"This is a long paragraph line", {10, 10, 160, 10}, 10, {}, {30, 30, 30}, 2};
    OcrBlock second{"continuing on the next line", {10, 22, 170, 10}, 10, {}, {30, 30, 30}, 2};
    LayoutOptions paragraph;
    paragraph.frame_width = 200;
    paragraph.frame_height = 100;
    paragraph.target_width = 200;
    paragraph.target_height = 100;
    paragraph.merge_paragraphs = true;
    const auto merged = BuildPresentLayout(
        {{first, "这是长段落的第一行", {}, false},
         {second, "并在下一行继续", {}, false}}, paragraph);
    CHECK(merged.size() == 1);
    if (!merged.empty()) {
      CHECK(merged[0].source.bbox.h > 20);
      CHECK(merged[0].translation.find("下一行") != std::string::npos);
      CHECK(!merged[0].center_text_vertically);
      CHECK(merged[0].cover_rects.size() == 2);
    }
    first.text = "File";
    first.bbox.w = 30;
    second.text = "Edit";
    second.bbox.w = 30;
    const auto labels = BuildPresentLayout(
        {{first, "文件", {}, false}, {second, "编辑", {}, false}}, paragraph);
    CHECK(labels.size() == 2);
    if (labels.size() == 2) CHECK(labels[0].center_text_vertically);
  }
  {
    OcrBlock tiny{"tiny", {10, 10, 40, 8}, 8, {}, {255, 255, 255}, 2};
    LayoutOptions retina;
    retina.frame_width = 200;
    retina.frame_height = 100;
    retina.target_width = 100;
    retina.target_height = 50;
    retina.target_pixels_per_unit = 2;
    const auto mac_layout = BuildPresentLayout({{tiny, "小字", {}, false}}, retina);
    LayoutOptions windows = retina;
    windows.target_width = 200;
    windows.target_height = 100;
    windows.target_pixels_per_unit = 1;
    const auto win_layout = BuildPresentLayout({{tiny, "小字", {}, false}}, windows);
    CHECK(mac_layout.size() == 1 && win_layout.size() == 1);
    if (!mac_layout.empty() && !win_layout.empty()) {
      CHECK(std::fabs(mac_layout[0].font_px * 2 - win_layout[0].font_px) < 0.1f);
      CHECK(mac_layout[0].font_px * 2 >= 6.0f);
      CHECK(win_layout[0].font_px >= 6.0f);
    }
    tiny.bbox.h = 100;
    tiny.line_height = 100;
    const auto capped_mac = BuildPresentLayout({{tiny, "大字", {}, false}}, retina);
    const auto capped_win = BuildPresentLayout({{tiny, "大字", {}, false}}, windows);
    CHECK(!capped_mac.empty() && capped_mac[0].font_px <= 10.0f);
    CHECK(!capped_win.empty() && capped_win[0].font_px <= 20.0f);
  }
  {
    int tr = 255, tg = 255, tb = 255;
    EnsureAaColor(tr, tg, tb, 0, 0, 0);
    CHECK(tr == 255 && tg == 255 && tb == 255);
  }
  {
    int tr = 0, tg = 0, tb = 0;
    EnsureAaColor(tr, tg, tb, 255, 255, 255);
    CHECK(tr == 0 && tg == 0 && tb == 0);
  }
  {
    int tr = 140, tg = 140, tb = 140;
    EnsureAaColor(tr, tg, tb, 128, 128, 128);
    CHECK(ContrastRatio(tr, tg, tb, 128, 128, 128) >= kWcagAaContrast);
    CHECK(tr != 140);
  }

  Settings s;
  CHECK(s.cloud_base_url.empty() && s.cloud_model.empty());
  CHECK(!CloudConfigured(s, ""));
  const std::string ser = SerializeSettings(s);
  CHECK(ser.find("api_key") == std::string::npos);
  CHECK(ser.find("openai.com") == std::string::npos);
  Settings s2 = ParseSettings(ser);
  CHECK(s2.engine == EnginePref::Auto);
  CHECK(s2.tgt_lang == "zh");
  s2.cloud_base_url = "https://example.invalid/v1";
  s2.privacy = true;
  s2.vk_new = 'Q';
  s2.mod_new = 3;
  const Settings s3 = ParseSettings(SerializeSettings(s2));
  CHECK(s3.privacy && s3.cloud_base_url == "https://example.invalid/v1");
  CHECK(s3.vk_new == 'Q' && s3.mod_new == 3);
  {
    const Settings bad = ParseSettings(
        "engine=garbage\n"
        "sticker_alpha=not-an-int\n"
        "font_scale=-500\n"
        "overlay_alpha=not-a-float\n"
        "vk_new=bad\n"
        "mod_new=3x\n");
    CHECK(bad.engine == EnginePref::Auto);
    CHECK(bad.sticker_alpha == 92);
    CHECK(bad.font_scale == 80);
    CHECK(std::isfinite(bad.overlay_alpha) && bad.overlay_alpha == 0.01f);
    CHECK(bad.vk_new == 'L' && bad.mod_new == 6);
  }
  {
    const Settings bounded = ParseSettings(
        "sticker_alpha=1\nfont_scale=999\noverlay_alpha=999\n");
    CHECK(bounded.sticker_alpha == 60);
    CHECK(bounded.font_scale == 150);
    CHECK(std::isfinite(bounded.overlay_alpha) && bounded.overlay_alpha == 0.10f);
  }

  OcrBlock blk;
  blk.text = "Hello";
  blk.bbox = {10, 10, 40, 12};
  Stabilizer st;
  std::vector<OcrBlock> committed;
  CHECK(!st.Feed({blk}, committed));
  CHECK(st.Feed({blk}, committed) && committed.size() == 1);
  blk.text = "Hello!";
  CHECK(!st.Feed({blk}, committed));

  Debounce db;
  auto t0 = std::chrono::steady_clock::now();
  CHECK(!db.Tick({blk}, t0, 300));
  CHECK(!db.Tick({blk}, t0 + std::chrono::milliseconds(100), 300));
  CHECK(db.Tick({blk}, t0 + std::chrono::milliseconds(301), 300));

  IdleWatch idle;
  idle.Motion(t0);
  CHECK(!idle.ShouldSleep(t0 + std::chrono::milliseconds(500)));
  CHECK(idle.ShouldSleep(t0 + std::chrono::milliseconds(2001)));
  idle.Motion(t0 + std::chrono::milliseconds(2500));
  CHECK(!idle.ShouldSleep(t0 + std::chrono::milliseconds(2501)));
  CHECK(idle.ShouldSleep(t0 + std::chrono::milliseconds(4501)));

  const auto p = BuildTranslatePrompt({.text = "It's on the house.", .tgt_lang = "zh"});
  CHECK(p.find("Simplified Chinese") != std::string::npos);
  CHECK(p.find("It's on the house.") != std::string::npos);

  static const char* kPairs[][2] = {
      {"Hello", "你好"},
      {"Thank you", "谢谢"},
      {"Good morning", "早上好"},
      {"How are you?", "你好吗？"},
      {"Please wait", "请稍候"},
      {"Settings", "设置"},
      {"Cancel", "取消"},
      {"Save", "保存"},
      {"It's on the house.", "免费招待。"},
      {"Click here", "点击这里"},
  };
  Settings auto_s;
  auto_s.engine = EnginePref::Auto;
  auto local_ok = MakeFakeEngine(EngineKind::Local, true, "本地译文", "");
  auto cloud_ok = MakeFakeEngine(EngineKind::Cloud, true, "云端译文", "");
  auto cloud_fail = MakeFakeEngine(EngineKind::Cloud, true, "", "timeout");
  auto cloud_down = MakeFakeEngine(EngineKind::Cloud, false, "", "not configured");
  TranslationCache dc;
  TranslateRequest hello;
  hello.text = "Hello";
  hello.src_lang = "en";
  hello.tgt_lang = "zh";
  {
    Settings priv = auto_s;
    priv.privacy = true;
    const auto r = DispatchTranslate(priv, local_ok.get(), cloud_ok.get(), &dc, hello);
    CHECK(r.text == "本地译文");
    CHECK(!r.from_cache);
  }
  {
    const auto r = DispatchTranslate(auto_s, local_ok.get(), cloud_ok.get(), &dc, hello);
    CHECK(r.from_cache && r.text == "本地译文");
  }
  dc.Clear();
  {
    TranslateRequest long_req = hello;
    long_req.text = std::string(201, 'a');
    const auto r = DispatchTranslate(auto_s, local_ok.get(), cloud_ok.get(), &dc, long_req);
    CHECK(r.text == "云端译文");
    CHECK(!r.from_cache);
  }
  {
    TranslateRequest long_req = hello;
    long_req.text = std::string(201, 'b');
    const auto r = DispatchTranslate(auto_s, local_ok.get(), cloud_fail.get(), &dc, long_req);
    CHECK(r.text == "本地译文");
  }
  {
    Settings cloud_lock;
    cloud_lock.engine = EnginePref::Cloud;
    TranslateRequest q;
    q.text = "x";
    const auto r = DispatchTranslate(cloud_lock, local_ok.get(), cloud_down.get(), &dc, q);
    CHECK(r.text == "本地译文");
  }
  {
    TranslationCache pair_cache;
    for (auto& pair : kPairs) {
      auto loc = MakeFakeEngine(EngineKind::Local, true, pair[1], "");
      TranslateRequest req;
      req.text = pair[0];
      req.src_lang = "en";
      const auto r = DispatchTranslate(auto_s, loc.get(), cloud_down.get(), &pair_cache, req);
      CHECK(r.text == std::string(pair[1]));
      const auto r2 = DispatchTranslate(auto_s, loc.get(), cloud_down.get(), &pair_cache, req);
      CHECK(r2.from_cache && r2.text == std::string(pair[1]));
    }
    CHECK(pair_cache.Size() == 10);
  }
  {
    auto empty_cloud = MakeCloudEngine("", "", "");
    CHECK(empty_cloud && !empty_cloud->Ready());
    TranslateRequest q;
    q.text = "hi";
    const auto cloud_miss = empty_cloud->Translate(q);
    CHECK(!cloud_miss.error.empty());
  }
  CHECK(DecidePresent(5.f, true, RenderLock::Auto) == PresentMode::Immersive);
  CHECK(DecidePresent(40.f, true, RenderLock::Auto) == PresentMode::StickerContrast);
  CHECK(FadeOverlayAlpha(true, 0) == 1.f);
  CHECK(FadeOverlayAlpha(false, 0) == 1.f);
  CHECK(FadeOverlayAlpha(false, 100) > 0.4f && FadeOverlayAlpha(false, 100) < 0.6f);
  CHECK(FadeOverlayAlpha(false, 200) == 0.f);
  CHECK(!HoverArmed(999));
  CHECK(HoverArmed(1000));
  CHECK(PointInOverlayBlock(12, 12, 10, 10, 20, 20));
  CHECK(!PointInOverlayBlock(5, 12, 10, 10, 20, 20));
  CHECK(FormatHotkey(6, 'L') == "Ctrl+Shift+L");
  CHECK(FormatHotkey(2, 'E') == "Ctrl+E");
  CHECK(FormatHotkey(2, 0xBC) == "Ctrl+,");
  {
    const int mods[] = {6, 2, 2, 6, 2};
    const int vks[] = {'L', 'E', 'T', 'H', 0xBC};
    CHECK(FindHotkeyConflict(mods, vks, 5) < 0);
    const int badm[] = {2, 2};
    const int badv[] = {'E', 'E'};
    CHECK(FindHotkeyConflict(badm, badv, 2) == 0);
  }

  CHECK(CloudTimeoutsMs{}.resolve == 3000 && CloudTimeoutsMs{}.send == 5000 &&
        CloudTimeoutsMs{}.receive == 15000);
  CHECK(ShouldRetryCloud("timeout"));
  CHECK(ShouldRetryCloud("http send failed"));
  CHECK(!ShouldRetryCloud("cloud not configured"));
  {
    const std::string sse =
        "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}\n"
        "data: {\"choices\":[{\"delta\":{\"content\":\"好\"}}]}\n"
        "data: [DONE]\n";
    CHECK(ParseChatCompletionBody(sse) == "你好");
    CHECK(ParseChatCompletionBody("{\"choices\":[{\"message\":{\"content\":\"单独\"}}]}") ==
          "单独");
    const auto body = BuildChatCompletionsJson("m", "hi\nthere", true);
    CHECK(body.find("\"stream\":true") != std::string::npos);
    CHECK(body.find("hi\\nthere") != std::string::npos);
  }
  {
    auto flaky = MakeFakeEngine(EngineKind::Cloud, true, "云端好了", "timeout", 1);
    Settings cloud_s;
    cloud_s.engine = EnginePref::Cloud;
    TranslateRequest q;
    q.text = std::string(201, 'x');
    TranslationCache c2;
    const auto r = DispatchTranslate(cloud_s, nullptr, flaky.get(), &c2, q);
    CHECK(r.text == "云端好了");
  }
  CHECK(RouteEngine({EnginePref::Auto, false, 0, true, true}) == EngineKind::Local);
  CHECK(RouteEngine({EnginePref::Cloud, true, 500, true, true}) == EngineKind::Local);
  {
    TranslationCache c3;
    Settings loc;
    loc.engine = EnginePref::Local;
    auto eng = MakeFakeEngine(EngineKind::Local, true, "A", "");
    TranslateRequest q1;
    q1.text = "same";
    q1.src_lang = "en";
    CHECK(DispatchTranslate(loc, eng.get(), nullptr, &c3, q1).text == "A");
    loc.src_lang = "ja";
    const auto miss = DispatchTranslate(loc, eng.get(), nullptr, &c3, q1);
    CHECK(!miss.from_cache);
  }

  {
    OcrBlock own;
    own.bbox = {10, 10, 40, 20};
    OcrBlock other;
    other.bbox = {200, 10, 40, 20};
    std::vector<OcrBlock> bl{own, other};
    FilterExcludedBlocks(bl, {{0, 0, 80, 80}});
    CHECK(bl.size() == 1 && bl[0].bbox.x == 200.f);
    const auto cap = ScreenRectToCapture(500, 400, 100, 50, 480, 390);
    CHECK(cap.x == 20.f && cap.y == 10.f);
  }
  {
    const auto s = ScalePhysBox({100, 100, 200, 200}, 96.f, 192.f);
    CHECK(s.x == 200 && s.w == 400);
    const auto c = ClampPhysBox({-50, 10, 200, 200}, 0, 0, 1920, 1080);
    CHECK(c.x == 0);
    const auto m = RemapAfterDisplayChange({100, 100, 400, 300}, 0, 0, 1920, 1080, 0, 0, 1280, 720);
    CHECK(m.w >= 160 && m.x >= 0);
  }
  {
    BoxPersist bp;
    bp.x = 12;
    bp.y = 34;
    bp.w = 400;
    bp.h = 240;
    bp.src_lang = "en";
    bp.tgt_lang = "ja";
    bp.engine = EnginePref::Local;
    bp.render = RenderLock::Sticker;
    const auto parsed = ParseBoxes(SerializeBoxes({bp}));
    CHECK(parsed.size() == 1);
    CHECK(parsed[0].x == 12 && parsed[0].tgt_lang == "ja");
    CHECK(parsed[0].engine == EnginePref::Local && parsed[0].render == RenderLock::Sticker);
  }

  {
    OcrBlock hi;
    hi.text = "Hi";
    hi.bbox = {10, 10, 40, 20};
    hi.bg_variance = 40;
    const auto bad = PlanPresent(hi, false, RenderLock::Auto, 20);
    CHECK(bad.covers_source && !IllegalTransparentStack(bad));
    const auto good = PlanPresent(hi, false, RenderLock::Auto, 92);
    CHECK(good.covers_source && !IllegalTransparentStack(good));
  }
  {
    OcrBlock src;
    src.text = "Hello";
    src.bg_variance = 40.f;
    constexpr float kTransPx = 20.f;
    const auto plan = PlanPresent(src, true, RenderLock::Auto, 92, kTransPx);
    CHECK(plan.mode == PresentMode::StickerContrast);
    CHECK(plan.show_source);
    CHECK(plan.source_text == "Hello");
    CHECK(plan.translation_font_px == kTransPx);
    CHECK(plan.source_font_px > kTransPx * 0.59f && plan.source_font_px < kTransPx * 0.61f);
  }
  {
    OcrBlock src;
    src.text = "Hi";
    src.bg_variance = 40.f;
    const auto plan = PlanPresent(src, false, RenderLock::Auto, 92, 16.f);
    CHECK(!plan.show_source);
    CHECK(plan.source_text.empty());
  }
  {
    OcrBlock invalid;
    invalid.text = "invalid";
    invalid.bbox = {0, 0, 0, 10};
    OcrBlock left;
    left.text = "Hello";
    left.bbox = {10, 10, 30, 20};
    OcrBlock right;
    right.text = "world";
    right.bbox = {48, 10, 30, 20};
    OcrBlock next;
    next.text = "Next";
    next.bbox = {10, 60, 50, 20};
    const auto normalized = NormalizeOcrBlocks({next, invalid, right, left}, 100, 100);
    CHECK(normalized.size() == 2);
    CHECK(normalized[0].text == "Hello world");
    CHECK(normalized[0].bbox.x == 10 && normalized[0].bbox.w == 68);
    CHECK(normalized[1].text == "Next");
  }
  {
    auto fake = MakeFakeEngine(EngineKind::Local, true, "translated text that wraps", "");
    TestCapture capture;
    TestOcr ocr;
    TestPresenter presenter;
    TranslationCache pipeline_cache;
    PipelineOptions options;
    options.settings.engine = EnginePref::Local;
    options.settings.src_lang = "en";
    options.settings.tgt_lang = "zh";
    options.target_width = 160;
    options.target_height = 120;
    Pipeline pipeline({&capture, &ocr, &presenter, fake.get(), nullptr, &pipeline_cache}, options);
    const auto first = pipeline.Step();
    CHECK(first.state == PipelineState::Watching && !first.stabilized && !first.rendered);
    const auto second = pipeline.Step();
    CHECK(second.state == PipelineState::Watching && second.stabilized && second.rendered);
    CHECK(second.blocks.size() == 2 && second.layout.size() == 2);
    if (second.blocks.size() == 2 && second.layout.size() == 2) {
      CHECK(!second.blocks[0].from_cache && !second.blocks[1].from_cache);
      CHECK(second.blocks[0].source.text == "Hello world");
      CHECK(second.layout[0].lines.size() >= 2);
      for (const auto& layout : second.layout) {
        CHECK(layout.rect.x >= 0 && layout.rect.y >= 0);
        CHECK(layout.rect.x + layout.rect.w <= options.target_width);
        CHECK(layout.rect.y + layout.rect.h <= options.target_height);
        CHECK(layout.rect.w > 0 && layout.rect.h > 0);
        CHECK(layout.covers_source && layout.background_alpha >= 0.60f);
        CHECK(layout.font_weight == 400);
        CHECK(layout.font_px >= 6 && layout.line_height_px >= layout.font_px);
        CHECK(layout.text_inset_x >= 1.5f && layout.text_inset_y >= 0.75f);
        CHECK(layout.mode == PresentMode::Immersive
                  ? layout.corner_radius == 0
                  : layout.corner_radius >= 1 && layout.corner_radius <= 2);
      }
      CHECK(second.layout[1].mode == PresentMode::Sticker);
    }
    CHECK(presenter.calls == 1 && presenter.last.blocks.size() == 2);
    pipeline.Pause();
    CHECK(pipeline.state() == PipelineState::Paused);
    const auto paused = pipeline.Step();
    CHECK(paused.state == PipelineState::Paused && capture.calls == 2);
    pipeline.Resume();
    CHECK(pipeline.state() == PipelineState::Idle);
    const auto cached = pipeline.Step();
    CHECK(cached.state == PipelineState::Watching && cached.stabilized && cached.rendered);
    CHECK(cached.blocks.size() == 2 && cached.layout.size() == 2);
    if (cached.blocks.size() == 2) {
      CHECK(cached.blocks[0].from_cache && cached.blocks[1].from_cache);
    }
    CHECK(capture.calls == 3 && ocr.calls == 3 && presenter.calls == 2);
    pipeline.Cancel();
    CHECK(pipeline.state() == PipelineState::Cancelled);
  }
  CHECK(QuoteRunPath("C:\\LensTrans\\app.exe") == "C:\\LensTrans\\app.exe");
  CHECK(QuoteRunPath("C:\\Program Files\\LensTrans\\app.exe") ==
        "\"C:\\Program Files\\LensTrans\\app.exe\"");
  CHECK(UnquoteRunPath("\"C:\\Program Files\\LensTrans\\app.exe\"") ==
        "C:\\Program Files\\LensTrans\\app.exe");
  CHECK(RunValuePointsTo("\"C:\\a b\\app.exe\"", "C:\\a b\\app.exe"));
  CHECK(!RunValuePointsTo("C:\\other.exe", "C:\\a\\app.exe"));

  CHECK(kDefaultGgufBytes == 1117320736ull);
  CHECK(IsDefaultGgufSha256(kDefaultGgufSha256));
  CHECK(IsDefaultGgufSha256("6A1A2EB6D15622BF3C96857206351BA97E1AF16C30D7A74EE38970E434E9407E"));
  CHECK(!IsDefaultGgufSha256("deadbeef"));
  CHECK(DefaultModelFileName() == kDefaultGgufFileName);
  CHECK(kLocalIdleUnloadMs == 10 * 60 * 1000);
  {
    const auto dir = std::filesystem::temp_directory_path() / "lenstrans-model-catalog-test";
    std::error_code ec;
    std::filesystem::remove_all(dir, ec);
    std::filesystem::create_directories(dir, ec);
    std::ofstream(dir / "z-model.gguf").put('z');
    std::ofstream(dir / "a-model.gguf").put('a');
    std::ofstream(dir / "ignored.txt").put('x');
    const auto models = GgufFilesIn(dir.string());
    CHECK(models.size() == 2);
    if (models.size() == 2) CHECK(models[0].find("a-model.gguf") != std::string::npos);
    std::ofstream(dir / "active-model.txt") << "z-model.gguf\n";
    CHECK(ActiveModelIn(dir.string()).find("z-model.gguf") != std::string::npos);
    std::filesystem::remove_all(dir, ec);
  }
#ifndef _WIN32
  {
    // Do not hardcode /workspace — CI checkouts live under /home/runner/work/...
    if (const char* prev = std::getenv("LENSTRANS_ROOT"); prev && *prev) {
      CHECK(FileExists(JoinPath(prev, "CMakeLists.txt")));
    } else {
      const std::string root = DetectRepoRoot();
      CHECK(FileExists(JoinPath(root, "CMakeLists.txt")) || FileExists("CMakeLists.txt"));
    }
  }
#endif

  if (g_fail) {
    std::fprintf(stderr, "%d checks failed\n", g_fail);
    return 1;
  }
  std::printf("test_core: all checks passed\n");
  return 0;
}
