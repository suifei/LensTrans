#pragma once

#include <string>

namespace lenstrans {

enum class RenderLock { Auto, Sticker, Immersive };
enum class PresentMode { Immersive, Sticker, StickerContrast };

constexpr float kImmersiveVariance = 18.0f;
constexpr float kWcagAaContrast = 4.5f;
constexpr float kSourceFontRatio = 0.6f;

inline PresentMode DecidePresent(float bg_variance, bool contrast, RenderLock lock) {
  if (lock == RenderLock::Sticker) {
    return contrast ? PresentMode::StickerContrast : PresentMode::Sticker;
  }
  if (lock == RenderLock::Immersive) return PresentMode::Immersive;
  if (bg_variance < kImmersiveVariance) return PresentMode::Immersive;
  return contrast ? PresentMode::StickerContrast : PresentMode::Sticker;
}

inline double RelativeLuminance(int r, int g, int b) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
}

inline double ContrastRatio(int tr, int tg, int tb, int br, int bg, int bb) {
  const double l1 = RelativeLuminance(tr, tg, tb);
  const double l2 = RelativeLuminance(br, bg, bb);
  const double hi = l1 > l2 ? l1 : l2;
  const double lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

// Contrast vs fill: return true if text RGB is far enough from fill (WCAG AA 4.5:1).
inline bool ContrastOk(int tr, int tg, int tb, int br, int bg, int bb) {
  return ContrastRatio(tr, tg, tb, br, bg, bb) >= kWcagAaContrast;
}

// PRD 4.2: below AA → text becomes inverse of fill RGB.
inline void EnsureAaColor(int& tr, int& tg, int& tb, int br, int bg, int bb) {
  if (ContrastRatio(tr, tg, tb, br, bg, bb) >= kWcagAaContrast) return;
  tr = 255 - br;
  tg = 255 - bg;
  tb = 255 - bb;
}

inline void InvertRgb(int& r, int& g, int& b) {
  r = 255 - r;
  g = 255 - g;
  b = 255 - b;
}

// No text → overlay fades to 0 over fade_ms (PRD 200ms).
inline float FadeOverlayAlpha(bool has_text, int empty_ms, int fade_ms = 200) {
  if (has_text) return 1.f;
  if (empty_ms <= 0) return 1.f;
  if (empty_ms >= fade_ms) return 0.f;
  return 1.f - static_cast<float>(empty_ms) / static_cast<float>(fade_ms);
}

inline bool HoverArmed(int hover_ms, int need_ms = 1000) { return hover_ms >= need_ms; }

inline bool PointInOverlayBlock(float x, float y, float bx, float by, float bw, float bh) {
  const float w = bw < 8.f ? 8.f : bw;
  const float h = bh < 8.f ? 8.f : bh;
  return x >= bx && y >= by && x < bx + w && y < by + h;
}

// Win32 RegisterHotKey bits: Alt=1 Ctrl=2 Shift=4 Win=8
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
  for (int i = 0; i < n; ++i) {
    for (int j = i + 1; j < n; ++j) {
      if (mods[i] == mods[j] && vks[i] == vks[j]) return i;
    }
  }
  return -1;
}

}  // namespace lenstrans
