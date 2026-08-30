#pragma once

#include "lenstrans/cache.hpp"
#include "lenstrans/dispatch.hpp"
#include "lenstrans/engine.hpp"
#include "lenstrans/frame_diff.hpp"
#include "lenstrans/ocr_block.hpp"
#include "lenstrans/pipeline.hpp"
#include "lenstrans/present.hpp"
#include "lenstrans/settings.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace lenstrans {

// Synthetic BGRA (top-left origin). No WGC.
inline void FillBgra(std::vector<std::uint8_t>& img, int w, int h, int b, int g, int r) {
  img.assign(static_cast<std::size_t>(w) * h * 4, 0);
  for (int i = 0; i < w * h; ++i) {
    img[static_cast<std::size_t>(i) * 4 + 0] = static_cast<std::uint8_t>(b);
    img[static_cast<std::size_t>(i) * 4 + 1] = static_cast<std::uint8_t>(g);
    img[static_cast<std::size_t>(i) * 4 + 2] = static_cast<std::uint8_t>(r);
    img[static_cast<std::size_t>(i) * 4 + 3] = 255;
  }
}

inline void FillRectBgra(std::vector<std::uint8_t>& img, int w, int h, int x0, int y0, int x1, int y1,
                         int b, int g, int r) {
  x0 = std::max(0, x0);
  y0 = std::max(0, y0);
  x1 = std::min(w, x1);
  y1 = std::min(h, y1);
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      const std::size_t i = static_cast<std::size_t>(y) * w + x;
      img[i * 4 + 0] = static_cast<std::uint8_t>(b);
      img[i * 4 + 1] = static_cast<std::uint8_t>(g);
      img[i * 4 + 2] = static_cast<std::uint8_t>(r);
      img[i * 4 + 3] = 255;
    }
  }
}

inline void FillCheckerBgra(std::vector<std::uint8_t>& img, int w, int h, int cell) {
  img.assign(static_cast<std::size_t>(w) * h * 4, 0);
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      const bool on = ((x / cell) + (y / cell)) & 1;
      const int v = on ? 40 : 220;
      const std::size_t i = static_cast<std::size_t>(y) * w + x;
      img[i * 4 + 0] = static_cast<std::uint8_t>(v);
      img[i * 4 + 1] = static_cast<std::uint8_t>(on ? 80 : 200);
      img[i * 4 + 2] = static_cast<std::uint8_t>(on ? 200 : 40);
      img[i * 4 + 3] = 255;
    }
  }
}

// 5×7 bitmap font, one glyph per letter A–Z / space. Enough to paint "HELLO".
inline void StampGlyph(std::vector<std::uint8_t>& img, int w, int h, int x, int y, char ch, int scale,
                       int b, int g, int r) {
  static const int kBits[27] = {
      0x7A5A, 0x7C5C, 0x7246, 0x6B5C, 0x724F, 0x724E, 0x7257, 0x5B5A, 0x7497, 0x3152, 0x5B4A,
      0x4247, 0x5F5A, 0x5F5A, 0x7B57, 0x7A4E, 0x7B76, 0x7A5A, 0x7246, 0x7492, 0x5B52, 0x5B52,
      0x5BD5, 0x5A5A, 0x5A92, 0x7319, 0x0000};
  int idx = 26;
  if (ch >= 'A' && ch <= 'Z') idx = ch - 'A';
  if (ch >= 'a' && ch <= 'z') idx = ch - 'a';
  const int bits = kBits[idx];
  for (int gy = 0; gy < 7; ++gy) {
    for (int gx = 0; gx < 5; ++gx) {
      if (((bits >> (gy * 5 + gx)) & 1) == 0) continue;
      FillRectBgra(img, w, h, x + gx * scale, y + gy * scale, x + (gx + 1) * scale,
                   y + (gy + 1) * scale, b, g, r);
    }
  }
}

inline void StampText(std::vector<std::uint8_t>& img, int w, int h, int x, int y, const char* text,
                      int scale) {
  for (int i = 0; text[i]; ++i) {
    StampGlyph(img, w, h, x + i * (5 * scale + scale), y, text[i], scale, 20, 20, 20);
  }
}

inline float SampleRingVariance(const std::vector<std::uint8_t>& img, int w, int h, const BBox& box) {
  const int x0 = std::max(0, static_cast<int>(box.x));
  const int y0 = std::max(0, static_cast<int>(box.y));
  const int x1 = std::min(w, static_cast<int>(box.x + box.w));
  const int y1 = std::min(h, static_cast<int>(box.y + box.h));
  const int ring = 6;
  double sr = 0, sg = 0, sb = 0, n = 0;
  auto pix = [&](int x, int y, const std::uint8_t*& p) -> bool {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    if (x >= x0 && x < x1 && y >= y0 && y < y1) return false;
    p = img.data() + (static_cast<std::size_t>(y) * w + x) * 4;
    return true;
  };
  const std::uint8_t* p = nullptr;
  for (int y = y0 - ring; y < y1 + ring; ++y) {
    for (int x = x0 - ring; x < x1 + ring; ++x) {
      if (!pix(x, y, p)) continue;
      sr += p[2];
      sg += p[1];
      sb += p[0];
      n += 1;
    }
  }
  if (n < 1) return 0.f;
  const double mr = sr / n, mg = sg / n, mb = sb / n;
  double vr = 0, vg = 0, vb = 0;
  for (int y = y0 - ring; y < y1 + ring; ++y) {
    for (int x = x0 - ring; x < x1 + ring; ++x) {
      if (!pix(x, y, p)) continue;
      vr += (p[2] - mr) * (p[2] - mr);
      vg += (p[1] - mg) * (p[1] - mg);
      vb += (p[0] - mb) * (p[0] - mb);
    }
  }
  return static_cast<float>(std::sqrt((vr + vg + vb) / (3.0 * n)));
}

struct PresentPlan {
  PresentMode mode = PresentMode::Immersive;
  bool covers_source = true;       // opaque fill or sticker >= 60
  bool draws_translation = true;
  bool translucent_stack = false;  // illegal: trans over source with see-through
  bool show_source = false;        // PRD 4.2: contrast mode shows original below sticker
  std::string source_text;
  float translation_font_px = 0.f;
  float source_font_px = 0.f;
};

inline PresentPlan PlanPresent(const OcrBlock& b, bool contrast, RenderLock lock, int sticker_alpha,
                               float translation_font_px = 14.f) {
  PresentPlan p;
  p.mode = DecidePresent(b.bg_variance, contrast, lock);
  p.draws_translation = true;
  p.translation_font_px = translation_font_px;
  if (p.mode == PresentMode::Immersive) {
    p.covers_source = true;
    p.translucent_stack = false;
  } else {
    p.covers_source = sticker_alpha >= 60;
    p.translucent_stack = !p.covers_source;
  }
  if (p.mode == PresentMode::StickerContrast) {
    p.show_source = true;
    p.source_text = b.text;
    p.source_font_px = translation_font_px * kSourceFontRatio;
  }
  return p;
}

inline bool IllegalTransparentStack(const PresentPlan& p) {
  return p.draws_translation && (!p.covers_source || p.translucent_stack);
}

struct InjectedRun {
  int diff_changed = 0;
  bool stabilized = false;
  std::string src_text;
  std::string translation;
  bool cache_hit = false;
  PresentPlan plan;
  float variance = 0;
};

// Injected-frame full chain: no WGC. Fake OCR from the known painted string.
inline InjectedRun RunInjectedFramePipeline(bool complex_bg, IEngine* engine, TranslationCache* cache,
                                            const char* painted = "HELLO") {
  constexpr int kW = 320, kH = 180;
  constexpr int kTx = 24, kTy = 48, kScale = 3;
  const int tw = static_cast<int>(std::char_traits<char>::length(painted)) * (5 * kScale + kScale);
  const int th = 7 * kScale;
  std::vector<std::uint8_t> prev, curr;
  if (complex_bg) {
    FillCheckerBgra(prev, kW, kH, 12);
    curr = prev;
  } else {
    FillBgra(prev, kW, kH, 245, 245, 245);
    FillBgra(curr, kW, kH, 245, 245, 245);
  }
  StampText(curr, kW, kH, kTx, kTy, painted, kScale);
  const auto diff = DiffFrames(prev.data(), curr.data(), kW, kH, kW * 4);
  OcrBlock blk;
  blk.text = painted;
  blk.bbox = {static_cast<float>(kTx), static_cast<float>(kTy), static_cast<float>(tw),
              static_cast<float>(th)};
  blk.line_height = static_cast<float>(th);
  blk.color = {20, 20, 20};
  blk.bg_variance = SampleRingVariance(curr, kW, kH, blk.bbox);
  Stabilizer st;
  std::vector<OcrBlock> committed;
  st.Feed({blk}, committed);
  const bool ok = st.Feed({blk}, committed);
  Settings s;
  s.engine = EnginePref::Local;
  s.sticker_alpha = 92;
  TranslateRequest req;
  req.text = blk.text;
  req.src_lang = "en";
  req.tgt_lang = "zh";
  auto r = DispatchTranslate(s, engine, nullptr, cache, req);
  auto r2 = DispatchTranslate(s, engine, nullptr, cache, req);
  InjectedRun out;
  out.diff_changed = diff.changed_count;
  out.stabilized = ok && committed.size() == 1;
  out.src_text = blk.text;
  out.translation = r2.text;
  out.cache_hit = r2.from_cache;
  out.variance = blk.bg_variance;
  out.plan = PlanPresent(blk, false, RenderLock::Auto, s.sticker_alpha);
  (void)r;
  return out;
}

}  // namespace lenstrans
