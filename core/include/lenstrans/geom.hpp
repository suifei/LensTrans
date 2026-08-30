#pragma once

#include "lenstrans/ocr_block.hpp"

#include <algorithm>
#include <vector>

namespace lenstrans {

struct RectF {
  float x = 0, y = 0, w = 0, h = 0;
};

inline bool RectsOverlap(float ax, float ay, float aw, float ah, float bx, float by, float bw,
                         float bh) {
  return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}

inline bool BlockHitsExclude(const OcrBlock& b, const RectF& ex) {
  return RectsOverlap(b.bbox.x, b.bbox.y, b.bbox.w, b.bbox.h, ex.x, ex.y, ex.w, ex.h);
}

// Drop blocks that hit any exclude rect (own settings/onboard/other LensTrans chrome).
inline void FilterExcludedBlocks(std::vector<OcrBlock>& blocks, const std::vector<RectF>& exclude) {
  std::vector<OcrBlock> keep;
  keep.reserve(blocks.size());
  for (auto& b : blocks) {
    bool hit = false;
    for (const auto& e : exclude) {
      if (BlockHitsExclude(b, e)) {
        hit = true;
        break;
      }
    }
    if (!hit) keep.push_back(std::move(b));
  }
  blocks.swap(keep);
}

// Map a screen-space exclude rect into capture-local pixels.
inline RectF ScreenRectToCapture(float sx, float sy, float sw, float sh, float cap_l, float cap_t) {
  return {sx - cap_l, sy - cap_t, sw, sh};
}

struct PhysBox {
  int x = 0, y = 0, w = 0, h = 0;
};

inline PhysBox ScalePhysBox(PhysBox b, float from_dpi, float to_dpi) {
  if (from_dpi <= 0.f || to_dpi <= 0.f) return b;
  const float s = to_dpi / from_dpi;
  auto rnd = [](float v) { return static_cast<int>(v >= 0 ? v + 0.5f : v - 0.5f); };
  b.x = rnd(static_cast<float>(b.x) * s);
  b.y = rnd(static_cast<float>(b.y) * s);
  b.w = std::max(160, rnd(static_cast<float>(b.w) * s));
  b.h = std::max(160, rnd(static_cast<float>(b.h) * s));
  return b;
}

inline PhysBox ClampPhysBox(PhysBox b, int virt_l, int virt_t, int virt_w, int virt_h) {
  if (virt_w <= 0 || virt_h <= 0) return b;
  const int r = virt_l + virt_w;
  const int bot = virt_t + virt_h;
  if (b.w > virt_w) b.w = virt_w;
  if (b.h > virt_h) b.h = virt_h;
  if (b.x < virt_l) b.x = virt_l;
  if (b.y < virt_t) b.y = virt_t;
  if (b.x + b.w > r) b.x = r - b.w;
  if (b.y + b.h > bot) b.y = bot - b.h;
  return b;
}

// Keep relative position on the virtual desktop after a display layout change.
inline PhysBox RemapAfterDisplayChange(PhysBox b, int old_l, int old_t, int old_w, int old_h,
                                       int new_l, int new_t, int new_w, int new_h) {
  if (old_w <= 0 || old_h <= 0) return ClampPhysBox(b, new_l, new_t, new_w, new_h);
  const float fx = static_cast<float>(b.x - old_l) / static_cast<float>(old_w);
  const float fy = static_cast<float>(b.y - old_t) / static_cast<float>(old_h);
  const float fw = static_cast<float>(b.w) / static_cast<float>(old_w);
  const float fh = static_cast<float>(b.h) / static_cast<float>(old_h);
  PhysBox n;
  n.x = new_l + static_cast<int>(fx * static_cast<float>(new_w));
  n.y = new_t + static_cast<int>(fy * static_cast<float>(new_h));
  n.w = std::max(160, static_cast<int>(fw * static_cast<float>(new_w)));
  n.h = std::max(160, static_cast<int>(fh * static_cast<float>(new_h)));
  return ClampPhysBox(n, new_l, new_t, new_w, new_h);
}

}  // namespace lenstrans
