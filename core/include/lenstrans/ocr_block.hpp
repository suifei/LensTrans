#pragma once

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace lenstrans {

// All OCR geometry is in capture pixels, with (0, 0) at the capture's top-left.
enum class CoordinateSpace { CaptureLocalTopLeft };
inline constexpr CoordinateSpace kOcrCoordinateSpace = CoordinateSpace::CaptureLocalTopLeft;

struct BBox {
  float x = 0;
  float y = 0;
  float w = 0;
  float h = 0;

  float right() const { return x + w; }
  float bottom() const { return y + h; }
  float center_y() const { return y + h * 0.5f; }
};

struct ColorRgb {
  std::uint8_t r = 0;
  std::uint8_t g = 0;
  std::uint8_t b = 0;
};

// Windows OCR and macOS Vision must both convert their native observations to this type.
struct OcrBlock {
  std::string text;
  BBox bbox;
  float line_height = 0;
  ColorRgb color{};
  ColorRgb background{255, 255, 255};
  float bg_variance = 0;
  std::vector<BBox> mask_boxes;
};

struct OcrMergeOptions {
  float max_horizontal_gap = 12.0f;
  float min_vertical_overlap = 0.25f;
};

inline bool IsFiniteBox(const BBox& box) {
  return std::isfinite(box.x) && std::isfinite(box.y) && std::isfinite(box.w) &&
         std::isfinite(box.h);
}

inline bool IsValidOcrBlock(const OcrBlock& block) {
  return !block.text.empty() && IsFiniteBox(block.bbox) && block.bbox.w > 0 && block.bbox.h > 0;
}

inline bool SameOcrLine(const OcrBlock& a, const OcrBlock& b,
                       float min_vertical_overlap = 0.25f) {
  const float top = std::max(a.bbox.y, b.bbox.y);
  const float bottom = std::min(a.bbox.bottom(), b.bbox.bottom());
  const float overlap = std::max(0.0f, bottom - top);
  const float shorter = std::max(1.0f, std::min(a.bbox.h, b.bbox.h));
  if (overlap / shorter >= min_vertical_overlap) return true;
  const float center_tolerance = std::max(1.0f, std::min(a.bbox.h, b.bbox.h) * 0.35f);
  return std::fabs(a.bbox.center_y() - b.bbox.center_y()) <= center_tolerance;
}

inline std::vector<OcrBlock> SortOcrBlocks(std::vector<OcrBlock> blocks) {
  std::stable_sort(blocks.begin(), blocks.end(), [](const OcrBlock& a, const OcrBlock& b) {
    const float tolerance = std::max(1.0f, std::min(a.bbox.h, b.bbox.h) * 0.5f);
    if (std::fabs(a.bbox.y - b.bbox.y) > tolerance) return a.bbox.y < b.bbox.y;
    if (std::fabs(a.bbox.x - b.bbox.x) > 0.01f) return a.bbox.x < b.bbox.x;
    return a.text < b.text;
  });
  return blocks;
}

inline std::string JoinOcrText(const std::string& left, const std::string& right) {
  if (left.empty()) return right;
  if (right.empty()) return left;
  const unsigned char last = static_cast<unsigned char>(left.back());
  const unsigned char first = static_cast<unsigned char>(right.front());
  const bool ascii_word = (last < 128 && (std::isalnum(last) || last == '\'')) &&
                          (first < 128 && (std::isalnum(first) || first == '\''));
  return left + (ascii_word ? " " : "") + right;
}

inline OcrBlock MergeOcrBlock(const OcrBlock& left, const OcrBlock& right) {
  OcrBlock merged = left;
  merged.text = JoinOcrText(left.text, right.text);
  const float x0 = std::min(left.bbox.x, right.bbox.x);
  const float y0 = std::min(left.bbox.y, right.bbox.y);
  const float x1 = std::max(left.bbox.right(), right.bbox.right());
  const float y1 = std::max(left.bbox.bottom(), right.bbox.bottom());
  merged.bbox = {x0, y0, x1 - x0, y1 - y0};
  merged.line_height = std::max(left.line_height, right.line_height);
  merged.bg_variance = std::max(left.bg_variance, right.bg_variance);
  return merged;
}

inline std::vector<OcrBlock> MergeOcrBlocks(const std::vector<OcrBlock>& input,
                                            OcrMergeOptions options = {}) {
  std::vector<OcrBlock> sorted = SortOcrBlocks(input);
  std::vector<OcrBlock> out;
  out.reserve(sorted.size());
  for (const auto& block : sorted) {
    if (out.empty()) {
      out.push_back(block);
      continue;
    }
    OcrBlock& previous = out.back();
    const float gap = block.bbox.x - previous.bbox.right();
    if (SameOcrLine(previous, block, options.min_vertical_overlap) &&
        gap <= options.max_horizontal_gap) {
      previous = MergeOcrBlock(previous, block);
    } else {
      out.push_back(block);
    }
  }
  return out;
}

inline std::vector<OcrBlock> NormalizeOcrBlocks(const std::vector<OcrBlock>& input, int frame_width = 0,
                                                int frame_height = 0,
                                                OcrMergeOptions merge = {}) {
  std::vector<OcrBlock> valid;
  valid.reserve(input.size());
  for (auto block : input) {
    if (!IsValidOcrBlock(block)) continue;
    if (frame_width > 0 && frame_height > 0) {
      const float x0 = std::max(0.0f, block.bbox.x);
      const float y0 = std::max(0.0f, block.bbox.y);
      const float x1 = std::min(static_cast<float>(frame_width), block.bbox.right());
      const float y1 = std::min(static_cast<float>(frame_height), block.bbox.bottom());
      if (x1 <= x0 || y1 <= y0) continue;
      block.bbox = {x0, y0, x1 - x0, y1 - y0};
    }
    if (!std::isfinite(block.line_height) || block.line_height <= 0) block.line_height = block.bbox.h;
    if (!std::isfinite(block.bg_variance) || block.bg_variance < 0) block.bg_variance = 0;
    valid.push_back(std::move(block));
  }
  return MergeOcrBlocks(valid, merge);
}

}  // namespace lenstrans
