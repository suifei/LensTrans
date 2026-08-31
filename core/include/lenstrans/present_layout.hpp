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
  // Physical pixels represented by one normalized layout unit. Platform adapters
  // derive this value before entering Core.
  float target_pixels_per_unit = 1.0f;
  PresentationSemantics presentation{};
  float margin_ratio = 0.12f;
  float line_height_ratio = 1.20f;
  int min_columns = 1;
  bool merge_paragraphs = false;
  float min_font_px = 8.0f;
  float min_font_physical_px = 9.0f;
  float max_font_physical_px = 20.0f;
  float emergency_min_font_physical_px = 6.0f;
  float max_font_px = 48.0f;
};

struct PresentBlockLayout {
  OcrBlock source;
  std::string translation;
  PresentMode mode = PresentMode::Immersive;
  LayoutRect rect;
  std::vector<std::string> lines;
  std::vector<LayoutRect> cover_rects;
  float font_px = 0;
  int font_weight = 400;
  float line_height_px = 0;
  float margin_px = 0;
  float text_inset_x = 0;
  float text_inset_y = 0;
  float corner_radius = 0;
  float background_alpha = 1.0f;
  bool covers_source = true;
  bool show_source = false;
  bool center_text_vertically = true;
  ColorRgb text_color{};
  ColorRgb fill_color{255, 255, 255};
};

struct ParagraphTranslationGroup {
  TranslatedBlock merged;
  std::vector<OcrBlock> sources;
};

inline bool ShouldMergeParagraphLines(const OcrBlock& current, const OcrBlock& next,
                                      int frame_width) {
  if (!IsValidOcrBlock(current) || !IsValidOcrBlock(next) || frame_width <= 0) return false;
  const float line = std::max(1.0f, std::max(current.line_height, next.line_height));
  const float gap = next.bbox.y - (current.bbox.y + current.bbox.h);
  if (gap < -line * 0.35f || gap > line * 0.9f) return false;
  if (std::fabs(next.bbox.x - current.bbox.x) > std::max(12.0f, line * 1.5f)) return false;
  const float widest = std::max(current.bbox.w, next.bbox.w);
  const auto current_chars = Utf8CodepointCount(current.text);
  const auto next_chars = Utf8CodepointCount(next.text);
  // Paragraph continuation lines are either wide in the captured frame or
  // substantially sentence-like. Short labels and menu rows stay independent.
  const bool next_is_line = next.bbox.w >= static_cast<float>(frame_width) * 0.35f ||
                            next_chars >= 16;
  return next_is_line && (widest >= static_cast<float>(frame_width) * 0.45f ||
                          current_chars >= 24);
}

inline bool IsRedundantParagraphTranslation(const std::string& existing,
                                             const std::string& candidate) {
  if (candidate.empty() || existing == candidate) return true;
  return Utf8CodepointCount(candidate) >= 8 &&
         existing.find(candidate) != std::string::npos;
}

inline std::vector<ParagraphTranslationGroup> MergeParagraphBlocks(
    const std::vector<TranslatedBlock>& blocks, int frame_width) {
  std::vector<ParagraphTranslationGroup> merged;
  merged.reserve(blocks.size());
  for (const auto& block : blocks) {
    if (merged.empty() || merged.back().merged.translation.empty() || block.translation.empty() ||
        !ShouldMergeParagraphLines(merged.back().merged.source, block.source, frame_width)) {
      merged.push_back({block, {block.source}});
      continue;
    }
    auto& group = merged.back();
    auto& current = group.merged;
    const float x0 = std::min(current.source.bbox.x, block.source.bbox.x);
    const float y0 = std::min(current.source.bbox.y, block.source.bbox.y);
    const float x1 = std::max(current.source.bbox.x + current.source.bbox.w,
                              block.source.bbox.x + block.source.bbox.w);
    const float y1 = std::max(current.source.bbox.y + current.source.bbox.h,
                              block.source.bbox.y + block.source.bbox.h);
    current.source.bbox = {x0, y0, x1 - x0, y1 - y0};
    current.source.line_height = std::max(current.source.line_height, block.source.line_height);
    current.source.text += "\n" + block.source.text;
    if (!IsRedundantParagraphTranslation(current.translation, block.translation))
      current.translation += " " + block.translation;
    current.source.bg_variance = std::max(current.source.bg_variance,
                                           block.source.bg_variance);
    group.sources.push_back(block.source);
  }
  for (auto& group : merged) {
    auto median_component = [&](auto component) {
      std::vector<std::uint8_t> values;
      values.reserve(group.sources.size());
      for (const auto& source : group.sources) values.push_back(component(source.background));
      const auto middle = values.begin() + values.size() / 2;
      std::nth_element(values.begin(), middle, values.end());
      return *middle;
    };
    group.merged.source.background = {
        median_component([](ColorRgb color) { return color.r; }),
        median_component([](ColorRgb color) { return color.g; }),
        median_component([](ColorRgb color) { return color.b; })};
  }
  return merged;
}

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
  const float target_scale = std::max(0.5f, options.target_pixels_per_unit);
  const float min_font = std::max(1.0f, options.min_font_physical_px / target_scale);
  const float max_font = std::min(options.max_font_px,
                                  options.max_font_physical_px / target_scale);
  const float emergency_min_font =
      std::max(1.0f, options.emergency_min_font_physical_px / target_scale);
  const float scale = std::max(0.5f, std::min(2.0f, options.presentation.font_scale / 100.0f));
  std::vector<float> source_lines;
  source_lines.reserve(blocks.size());
  for (const auto& bound : blocks) {
    if (!IsValidOcrBlock(bound.source)) continue;
    source_lines.push_back(std::max(bound.source.bbox.h * sy,
                                    std::max(1.0f, bound.source.line_height * sy)));
  }
  float median_line = min_font / 0.82f;
  if (!source_lines.empty()) {
    const auto middle = source_lines.begin() + source_lines.size() / 2;
    std::nth_element(source_lines.begin(), middle, source_lines.end());
    median_line = *middle;
  }
  std::vector<ParagraphTranslationGroup> render_blocks;
  if (options.merge_paragraphs) {
    render_blocks = MergeParagraphBlocks(blocks, options.frame_width);
  } else {
    render_blocks.reserve(blocks.size());
    for (const auto& block : blocks) render_blocks.push_back({block, {block.source}});
  }
  for (const auto& group : render_blocks) {
    const auto& bound = group.merged;
    if (!IsValidOcrBlock(bound.source) || bound.translation.empty()) continue;
    const auto& source = bound.source;
    const float source_h = std::max(1.0f, source.bbox.h * sy);
    const float margin = std::max(1.0f / target_scale,
                                  std::min(8.0f / target_scale,
                                           source_h * options.margin_ratio));
    LayoutRect rect{source.bbox.x * sx - margin, source.bbox.y * sy - margin,
                    source.bbox.w * sx + margin * 2.0f, source.bbox.h * sy + margin * 2.0f};
    rect = ClampLayoutRect(rect, options.target_width, options.target_height);
    if (rect.w <= 0 || rect.h <= 0) continue;

    const float raw_source_line = std::max(source_h, std::max(1.0f, source.line_height * sy));
    const float source_line = std::min(raw_source_line, std::max(min_font / 0.82f,
                                                                 median_line * 1.05f));
    const float estimate = std::max(min_font,
                                    std::min(max_font, source_line * 0.82f * scale));
    const int columns = std::max(options.min_columns,
                                 static_cast<int>((rect.w - margin * 2.0f) / std::max(4.0f, estimate * 0.72f)));
    PresentBlockLayout layout;
    layout.source = source;
    layout.translation = bound.translation;
    layout.mode = DecidePresent(source.bg_variance, options.presentation.contrast,
                                options.presentation.lock);
    const PresentPlan plan = PlanPresent(source, options.presentation.contrast,
                                         options.presentation.lock,
                                         options.presentation.sticker_alpha, estimate);
    layout.rect = rect;
    for (const auto& mask_source : group.sources) {
      const auto masks = mask_source.mask_boxes.empty()
                             ? std::vector<BBox>{mask_source.bbox}
                             : mask_source.mask_boxes;
      for (const auto& source_mask : masks) {
        const float mask_h = std::max(1.0f, source_mask.h * sy);
        const float mask_pad = std::max(1.0f / target_scale,
                                        std::min(3.0f / target_scale, mask_h * 0.10f));
        auto mask = ClampLayoutRect(
            {source_mask.x * sx - mask_pad, source_mask.y * sy - mask_pad,
             source_mask.w * sx + mask_pad * 2, source_mask.h * sy + mask_pad * 2},
            options.target_width, options.target_height);
        if (mask.w > 0 && mask.h > 0) layout.cover_rects.push_back(mask);
      }
    }
    layout.lines = WrapUtf8(layout.translation, columns);
    layout.center_text_vertically = layout.lines.size() == 1;
    const float line_count = static_cast<float>(std::max<std::size_t>(1, layout.lines.size()));
    const float target_fraction = plan.show_source ? 0.68f : 1.0f;
    const float available_h = std::max(1.0f, (rect.h - margin * 2.0f) * target_fraction);
    const float fit_font = available_h / (line_count * options.line_height_ratio);
    layout.font_px = std::max(emergency_min_font,
                              std::min(max_font, std::min(estimate, fit_font)));
    layout.font_weight = 400;
    layout.line_height_px = std::max(layout.font_px, std::min(available_h / line_count,
                                                               layout.font_px * options.line_height_ratio));
    layout.margin_px = margin;
    layout.text_inset_x = std::max(1.5f / target_scale,
                                   std::min(3.0f / target_scale, margin));
    layout.text_inset_y = std::max(0.75f / target_scale,
                                   std::min(2.0f / target_scale, margin * 0.75f));
    layout.corner_radius = layout.mode == PresentMode::Immersive
                               ? 0.0f
                               : std::max(1.0f / target_scale,
                                          std::min(2.0f / target_scale, rect.h * 0.12f));
    layout.fill_color = source.background;
    layout.text_color = AccessibleTextColor(layout.fill_color);
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
    int font_scale = 100, float target_pixels_per_unit = 1.0f) {
  LayoutOptions options;
  options.frame_width = frame_w;
  options.frame_height = frame_h;
  options.target_width = panel_w;
  options.target_height = panel_h;
  options.target_pixels_per_unit = target_pixels_per_unit;
  options.presentation.lock = lock;
  options.presentation.contrast = contrast;
  options.presentation.sticker_alpha = sticker_alpha;
  options.presentation.font_scale = font_scale;
  return BuildPresentLayout(BindTranslations(blocks, translations), options);
}

}  // namespace lenstrans
