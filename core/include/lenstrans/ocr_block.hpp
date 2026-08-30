#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace lenstrans {

// Device-independent pixels, origin = capture-region top-left.
struct BBox {
  float x = 0;
  float y = 0;
  float w = 0;
  float h = 0;
};

struct ColorRgb {
  std::uint8_t r = 0;
  std::uint8_t g = 0;
  std::uint8_t b = 0;
};

// Cross-platform OCR block. Windows.Media.OCR and Vision must both fill this.
struct OcrBlock {
  std::string text;
  BBox bbox;
  float line_height = 0;
  ColorRgb color;
  float bg_variance = 0;  // 0 ≈ solid fill → immersive replace; high → sticker
};

}  // namespace lenstrans
