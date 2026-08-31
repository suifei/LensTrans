#pragma once

#include "lenstrans/ocr_block.hpp"

#include <algorithm>
#include <cmath>
#include <string>

namespace lenstrans {

enum class RenderLock { Auto, Sticker, Immersive };
enum class PresentMode { Immersive, Sticker, StickerContrast };

constexpr float kImmersiveVariance = 18.0f;
constexpr float kWcagAaContrast = 4.5f;
constexpr float kSourceFontRatio = 0.6f;

struct PresentationSemantics {
  RenderLock lock = RenderLock::Auto;
  PresentMode mode = PresentMode::Immersive;
  bool contrast = false;
  int sticker_alpha = 92;
  int font_scale = 100;
};

inline PresentMode DecidePresent(float bg_variance, bool contrast, RenderLock lock) {
  if (lock == RenderLock::Sticker) return contrast ? PresentMode::StickerContrast : PresentMode::Sticker;
  if (lock == RenderLock::Immersive) return PresentMode::Immersive;
  if (std::isfinite(bg_variance) && bg_variance < kImmersiveVariance) return PresentMode::Immersive;
  return contrast ? PresentMode::StickerContrast : PresentMode::Sticker;
}

inline double SrgbChannel(double value) {
  const double c = std::max(0.0, std::min(255.0, value)) / 255.0;
  return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
}

inline double RelativeLuminance(int r, int g, int b) {
  return 0.2126 * SrgbChannel(r) + 0.7152 * SrgbChannel(g) + 0.0722 * SrgbChannel(b);
}

inline double ContrastRatio(int tr, int tg, int tb, int br, int bg, int bb) {
  const double l1 = RelativeLuminance(tr, tg, tb);
  const double l2 = RelativeLuminance(br, bg, bb);
  const double hi = std::max(l1, l2);
  const double lo = std::min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

inline bool ContrastOk(int tr, int tg, int tb, int br, int bg, int bb) {
  return ContrastRatio(tr, tg, tb, br, bg, bb) >= kWcagAaContrast;
}

// Chooses the better of black and white. Unlike merely inverting RGB, this always picks
// the strongest of the two renderer-independent colors.
inline ColorRgb AccessibleTextColor(const ColorRgb& fill) {
  const double black = ContrastRatio(0, 0, 0, fill.r, fill.g, fill.b);
  const double white = ContrastRatio(255, 255, 255, fill.r, fill.g, fill.b);
  return black >= white ? ColorRgb{0, 0, 0} : ColorRgb{255, 255, 255};
}

// Kept for source compatibility with the first Core API. New code should use
// AccessibleTextColor when it needs a guaranteed readable color.
inline void EnsureAaColor(int& tr, int& tg, int& tb, int br, int bg, int bb) {
  if (ContrastRatio(tr, tg, tb, br, bg, bb) >= kWcagAaContrast) return;
  const ColorRgb chosen = AccessibleTextColor({static_cast<std::uint8_t>(br),
                                                static_cast<std::uint8_t>(bg),
                                                static_cast<std::uint8_t>(bb)});
  tr = chosen.r;
  tg = chosen.g;
  tb = chosen.b;
}

inline void InvertRgb(int& r, int& g, int& b) {
  r = 255 - r;
  g = 255 - g;
  b = 255 - b;
}

struct PresentPlan {
  PresentMode mode = PresentMode::Immersive;
  bool covers_source = true;
  bool draws_translation = true;
  bool translucent_stack = false;
  bool show_source = false;
  std::string source_text;
  float background_alpha = 1.0f;
  float translation_font_px = 0;
  float source_font_px = 0;
  ColorRgb text_color{};
  ColorRgb fill_color{255, 255, 255};
};

inline PresentPlan PlanPresent(const OcrBlock& block, bool contrast, RenderLock lock,
                               int sticker_alpha, float translation_font_px = 14.0f) {
  PresentPlan plan;
  plan.mode = DecidePresent(block.bg_variance, contrast, lock);
  plan.translation_font_px = std::max(1.0f, translation_font_px);
  plan.fill_color = block.background;
  plan.text_color = AccessibleTextColor(plan.fill_color);
  if (plan.mode == PresentMode::Immersive) {
    plan.background_alpha = 1.0f;
  } else {
    plan.background_alpha = std::max(0, std::min(100, sticker_alpha)) / 100.0f;
    plan.covers_source = plan.background_alpha >= 0.60f;
    plan.translucent_stack = !plan.covers_source;
  }
  if (plan.mode == PresentMode::StickerContrast) {
    plan.show_source = true;
    plan.source_text = block.text;
    plan.source_font_px = plan.translation_font_px * kSourceFontRatio;
  }
  return plan;
}

inline bool IllegalTransparentStack(const PresentPlan& plan) {
  return plan.draws_translation && (!plan.covers_source || plan.translucent_stack);
}

inline float FadeOverlayAlpha(bool has_text, int empty_ms, int fade_ms = 200) {
  if (has_text || empty_ms <= 0) return 1.0f;
  if (fade_ms <= 0 || empty_ms >= fade_ms) return 0.0f;
  return 1.0f - static_cast<float>(empty_ms) / static_cast<float>(fade_ms);
}

inline bool HoverArmed(int hover_ms, int need_ms = 1000) { return hover_ms >= need_ms; }

inline bool PointInOverlayBlock(float x, float y, float bx, float by, float bw, float bh) {
  const float w = std::max(8.0f, bw);
  const float h = std::max(8.0f, bh);
  return x >= bx && y >= by && x < bx + w && y < by + h;
}

inline std::string FormatHotkey(int mod, int vk) {
  std::string s;
  if (mod & 1) s += "Alt+";
  if (mod & 2) s += "Ctrl+";
  if (mod & 4) s += "Shift+";
  if (mod & 8) s += "Win+";
  if (vk >= 'A' && vk <= 'Z') s += static_cast<char>(vk);
  else if (vk >= '0' && vk <= '9') s += static_cast<char>(vk);
  else if (vk == 0xBC) s += ",";
  else if (vk == 0x20) s += "Space";
  else s += "VK" + std::to_string(vk);
  return s;
}

inline int FindHotkeyConflict(const int* mods, const int* vks, int n) {
  if (!mods || !vks || n <= 0) return -1;
  for (int i = 0; i < n; ++i)
    for (int j = i + 1; j < n; ++j)
      if (mods[i] == mods[j] && vks[i] == vks[j]) return i;
  return -1;
}

}  // namespace lenstrans
