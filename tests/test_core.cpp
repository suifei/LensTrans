#include "lenstrans/autostart.hpp"
#include "lenstrans/boxes.hpp"
#include "lenstrans/cache.hpp"
#include "lenstrans/cloud_http.hpp"
#include "lenstrans/geom.hpp"
#include "lenstrans/inject_pipeline.hpp"
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

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
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

int main() {
  // SHA-1: "abc" → a9993e364706816aba3e25717850c26c9cd0d89d
  CHECK(Sha1Hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d");
  CHECK(CacheKey("en", "hello") == Sha1Hex(std::string("en") + "hello"));
  CHECK(CacheKey("en", "hello") != CacheKey("zh", "hello"));

  TranslationCache cache;
  std::string miss;
  CHECK(!cache.Get("k", miss));
  cache.Put(CacheKey("en", "hi"), "你好");
  std::string hit;
  CHECK(cache.Get(CacheKey("en", "hi"), hit) && hit == "你好");
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
    CHECK(tr == 127 && tg == 127 && tb == 127);
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
  CHECK(p.find("简体中文") != std::string::npos);
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
    auto fake = MakeFakeEngine(EngineKind::Local, true, "你好", "");
    TranslationCache ic;
    const auto solid = RunInjectedFramePipeline(false, fake.get(), &ic, "HELLO");
    CHECK(solid.diff_changed >= 1);
    CHECK(solid.stabilized);
    CHECK(solid.src_text == "HELLO");
    CHECK(solid.translation == "你好");
    CHECK(solid.cache_hit);
    CHECK(solid.variance < kImmersiveVariance);
    CHECK(solid.plan.mode == PresentMode::Immersive);
    CHECK(solid.plan.covers_source);
    CHECK(!IllegalTransparentStack(solid.plan));
    TranslationCache ic2;
    const auto busy = RunInjectedFramePipeline(true, fake.get(), &ic2, "HELLO");
    CHECK(busy.diff_changed >= 1);
    CHECK(busy.stabilized);
    CHECK(busy.variance >= kImmersiveVariance);
    CHECK(busy.plan.mode == PresentMode::Sticker);
    CHECK(busy.plan.covers_source);
    CHECK(!IllegalTransparentStack(busy.plan));
    OcrBlock hi;
    hi.bg_variance = 40;
    const auto bad = PlanPresent(hi, false, RenderLock::Auto, 20);
    CHECK(IllegalTransparentStack(bad));
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
  CHECK(QuoteRunPath("C:\\LensTrans\\app.exe") == "C:\\LensTrans\\app.exe");
  CHECK(QuoteRunPath("C:\\Program Files\\LensTrans\\app.exe") ==
        "\"C:\\Program Files\\LensTrans\\app.exe\"");
  CHECK(UnquoteRunPath("\"C:\\Program Files\\LensTrans\\app.exe\"") ==
        "C:\\Program Files\\LensTrans\\app.exe");
  CHECK(RunValuePointsTo("\"C:\\a b\\app.exe\"", "C:\\a b\\app.exe"));
  CHECK(!RunValuePointsTo("C:\\other.exe", "C:\\a\\app.exe"));

  CHECK(kDefaultGgufBytes == 491400032ull);
  CHECK(IsDefaultGgufSha256(kDefaultGgufSha256));
  CHECK(IsDefaultGgufSha256("74A4DA8C9FDBCD15BD1F6D01D621410D31C6FC00986F5EB687824E7B93D7A9DB"));
  CHECK(!IsDefaultGgufSha256("deadbeef"));
  CHECK(DefaultModelFileName() == kDefaultGgufFileName);
  CHECK(kLocalIdleUnloadMs == 10 * 60 * 1000);
#ifndef _WIN32
  {
    setenv("LENSTRANS_ROOT", "/workspace", 1);
    const std::string root = DetectRepoRoot();
    CHECK(FileExists(JoinPath(root, "CMakeLists.txt")));
    unsetenv("LENSTRANS_ROOT");
  }
#endif

  if (g_fail) {
    std::fprintf(stderr, "%d checks failed\n", g_fail);
    return 1;
  }
  std::printf("test_core: all checks passed\n");
  return 0;
}
