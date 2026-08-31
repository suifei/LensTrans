#pragma once

#include "lenstrans/present.hpp"
#include "lenstrans/text.hpp"
#include "lenstrans/translation.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace lenstrans {

struct LayoutRect {
  float x = 0;
  float y = 0;
  float w = 0;
  float h = 0;
};

struct LayoutOptions {
  int frame_width = 0;
  int frame_height = 0;
  int target_width = 0;
  int target_height = 0;
  PresentationSemantics presentation{};
  float margin_ratio = 0.12f;
  float line_height_ratio = 1.20f;
  int min_columns = 1;
  float min_font_px = 8.0f;
  float max_font_px = 48.0f;
};

struct PresentBlockLayout {
  OcrBlock source;
  std::string translation;
  PresentMode mode = PresentMode::Immersive;
  LayoutRect rect;
  std::vector<std::string> lines;
  float font_px = 0;
  float line_height_px = 0;
  float margin_px = 0;
  float background_alpha = 1.0f;
  bool covers_source = true;
  bool show_source = false;
  ColorRgb text_color{};
  ColorRgb fill_color{255, 255, 255};
};

inline LayoutRect ClampLayoutRect(LayoutRect rect, int width, int height) {
  if (width <= 0 || height <= 0) return {};
  rect.x = std::max(0.0f, std::min(rect.x, static_cast<float>(width)));
  rect.y = std::max(0.0f, std::min(rect.y, static_cast<float>(height)));
  rect.w = std::max(0.0f, std::min(rect.w, static_cast<float>(width) - rect.x));
  rect.h = std::max(0.0f, std::min(rect.h, static_cast<float>(height) - rect.y));
  return rect;
}

inline std::vector<PresentBlockLayout> BuildPresentLayout(const std::vector<TranslatedBlock>& blocks,
                                                           const LayoutOptions& options) {
  std::vector<PresentBlockLayout> out;
  if (options.frame_width <= 0 || options.frame_height <= 0 || options.target_width <= 0 ||
      options.target_height <= 0)
    return out;
  const float sx = static_cast<float>(options.target_width) / options.frame_width;
  const float sy = static_cast<float>(options.target_height) / options.frame_height;
  const float scale = std::max(0.5f, std::min(2.0f, options.presentation.font_scale / 100.0f));
  for (const auto& bound : blocks) {
    if (!IsValidOcrBlock(bound.source) || bound.translation.empty()) continue;
    const auto& source = bound.source;
    const float source_h = std::max(1.0f, source.bbox.h * sy);
    const float margin = std::max(1.0f, std::min(8.0f, source_h * options.margin_ratio));
    LayoutRect rect{source.bbox.x * sx - margin, source.bbox.y * sy - margin,
                    source.bbox.w * sx + margin * 2.0f, source.bbox.h * sy + margin * 2.0f};
    rect = ClampLayoutRect(rect, options.target_width, options.target_height);
    if (rect.w <= 0 || rect.h <= 0) continue;

    const float estimate = std::max(options.min_font_px,
                                    std::min(options.max_font_px, source_h * 0.82f * scale));
    const int columns = std::max(options.min_columns,
                                 static_cast<int>((rect.w - margin * 2.0f) / std::max(4.0f, estimate * 0.72f)));
    PresentBlockLayout layout;
    layout.source = source;
    layout.translation = bound.translation;
    layout.mode = DecidePresent(source.bg_variance, options.presentation.contrast,
                                options.presentation.lock);
    layout.rect = rect;
    layout.lines = WrapUtf8(layout.translation, columns);
    const float line_count = static_cast<float>(std::max<std::size_t>(1, layout.lines.size()));
    const float available_h = std::max(1.0f, rect.h - margin * 2.0f);
    const float fit_font = available_h / (line_count * options.line_height_ratio);
    layout.font_px = std::max(options.min_font_px, std::min(options.max_font_px, std::min(estimate, fit_font)));
    layout.line_height_px = std::max(layout.font_px, std::min(available_h / line_count,
                                                               layout.font_px * options.line_height_ratio));
    layout.margin_px = margin;
    layout.fill_color = source.background;
    layout.text_color = AccessibleTextColor(layout.fill_color);
    const PresentPlan plan = PlanPresent(source, options.presentation.contrast, options.presentation.lock,
                                         options.presentation.sticker_alpha, layout.font_px);
    layout.background_alpha = plan.background_alpha;
    layout.covers_source = plan.covers_source;
    layout.show_source = plan.show_source;
    out.push_back(std::move(layout));
  }
  return out;
}

// Compatibility adapter for the original platform call sites.
inline std::vector<PresentBlockLayout> BuildPresentLayout(
    const std::vector<OcrBlock>& blocks, const std::vector<std::string>& translations, int frame_w,
    int frame_h, int panel_w, int panel_h, bool contrast, RenderLock lock, int sticker_alpha,
    int font_scale = 100) {
  LayoutOptions options;
  options.frame_width = frame_w;
  options.frame_height = frame_h;
  options.target_width = panel_w;
  options.target_height = panel_h;
  options.presentation.lock = lock;
  options.presentation.contrast = contrast;
  options.presentation.sticker_alpha = sticker_alpha;
  options.presentation.font_scale = font_scale;
  return BuildPresentLayout(BindTranslations(blocks, translations), options);
}

}  // namespace lenstrans
