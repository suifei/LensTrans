#include "LenstransCoreBridge.h"

#include "lenstrans/engine.hpp"
#include "lenstrans/pipeline.hpp"
#include "lenstrans/present_layout.hpp"
#include "lenstrans/router.hpp"
#include "lenstrans/translation.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

namespace {

bool finite(float value) { return std::isfinite(value); }

bool valid_block(const LenstransCoreBlock &input) {
  return input.text && input.text[0] && finite(input.x) && finite(input.y) &&
         finite(input.width) && finite(input.height) && input.width > 0 && input.height > 0;
}

lenstrans::OcrBlock to_block(const LenstransCoreBlock &input) {
  lenstrans::OcrBlock block;
  if (input.text) block.text = input.text;
  block.bbox = {input.x, input.y, input.width, input.height};
  block.line_height = input.line_height;
  block.color = {input.red, input.green, input.blue};
  block.background = {input.background_red, input.background_green, input.background_blue};
  block.bg_variance = input.background_variance;
  return block;
}

lenstrans::RenderLock to_lock(int value) {
  if (value == 1) return lenstrans::RenderLock::Sticker;
  if (value == 2) return lenstrans::RenderLock::Immersive;
  return lenstrans::RenderLock::Auto;
}

void copy_string(const std::string &value, char *out, size_t capacity) {
  if (!out || capacity == 0) return;
  const size_t count = std::min(value.size(), capacity - 1);
  std::memcpy(out, value.data(), count);
  out[count] = '\0';
}

}  // namespace

extern "C" int lenstrans_core_transition(int state, int event) {
  try {
    using lenstrans::BoxState;
    if (state < LT_BOX_HIDDEN || state > LT_BOX_PAUSED) return LT_BOX_HIDDEN;
    const auto current = static_cast<BoxState>(state);
    switch (event) {
      case LT_BOX_EVENT_SHOW:
        return static_cast<int>(current == BoxState::Hidden ? BoxState::Editing : current);
      case LT_BOX_EVENT_EDIT:
        return static_cast<int>(current == BoxState::Hidden ? BoxState::Hidden : BoxState::Editing);
      case LT_BOX_EVENT_WATCH:
        return static_cast<int>(current == BoxState::Hidden ? BoxState::Hidden : BoxState::Watching);
      case LT_BOX_EVENT_PAUSE:
        return static_cast<int>(current == BoxState::Hidden ? BoxState::Hidden : BoxState::Paused);
      case LT_BOX_EVENT_HIDE:
        return static_cast<int>(BoxState::Hidden);
      case LT_BOX_EVENT_TOGGLE_EDIT:
        if (current == BoxState::Hidden) return LT_BOX_HIDDEN;
        return static_cast<int>((current == BoxState::Editing) ? BoxState::Watching
                                                                 : BoxState::Editing);
      default:
        return static_cast<int>(current);
    }
  } catch (...) {
    return LT_BOX_HIDDEN;
  }
}

extern "C" int lenstrans_core_route(int preference, int privacy, size_t text_chars,
                                     int local_ready, int cloud_ready) {
  try {
    const auto pref = preference == LT_ENGINE_LOCAL
                          ? lenstrans::EnginePref::Local
                          : preference == LT_ENGINE_CLOUD ? lenstrans::EnginePref::Cloud
                                                          : lenstrans::EnginePref::Auto;
    const auto kind = lenstrans::RouteEngine(
        {pref, privacy != 0, text_chars, local_ready != 0, cloud_ready != 0});
    if (kind == lenstrans::EngineKind::Local) return LT_ENGINE_KIND_LOCAL;
    if (kind == lenstrans::EngineKind::Cloud) return LT_ENGINE_KIND_CLOUD;
  } catch (...) {
  }
  return LT_ENGINE_NONE;
}

extern "C" int lenstrans_core_present_mode(float background_variance, int contrast,
                                             int render_lock) {
  try {
    const auto mode = lenstrans::DecidePresent(background_variance, contrast != 0, to_lock(render_lock));
    if (mode == lenstrans::PresentMode::StickerContrast) return LT_PRESENT_STICKER_CONTRAST;
    if (mode == lenstrans::PresentMode::Sticker) return LT_PRESENT_STICKER;
  } catch (...) {
  }
  return LT_PRESENT_IMMERSIVE;
}

extern "C" int lenstrans_core_layout_block(const LenstransCoreBlock *input, const char *translation,
                                             int frame_width, int frame_height, int target_width,
                                             int target_height, int contrast, int render_lock,
                                             int sticker_alpha, int font_scale,
                                             LenstransCoreLayout *out) {
  if (!input || !translation || !out || !valid_block(*input) || !translation[0] ||
      frame_width <= 0 || frame_height <= 0 || target_width <= 0 || target_height <= 0)
    return 0;
  try {
    std::vector<lenstrans::TranslatedBlock> blocks;
    blocks.push_back({to_block(*input), translation, {}, false});
    lenstrans::LayoutOptions options;
    options.frame_width = frame_width;
    options.frame_height = frame_height;
    options.target_width = target_width;
    options.target_height = target_height;
    options.presentation.lock = to_lock(render_lock);
    options.presentation.contrast = contrast != 0;
    options.presentation.sticker_alpha = std::max(0, std::min(100, sticker_alpha));
    options.presentation.font_scale = std::max(1, std::min(400, font_scale));
    const auto layouts = lenstrans::BuildPresentLayout(blocks, options);
    if (layouts.empty()) return 0;
    const auto &layout = layouts.front();
    out->x = layout.rect.x;
    out->y = layout.rect.y;
    out->width = layout.rect.w;
    out->height = layout.rect.h;
    out->font_px = layout.font_px;
    out->line_height_px = layout.line_height_px;
    out->margin_px = layout.margin_px;
    out->background_alpha = layout.background_alpha;
    out->mode = layout.mode == lenstrans::PresentMode::StickerContrast
                    ? LT_PRESENT_STICKER_CONTRAST
                    : layout.mode == lenstrans::PresentMode::Sticker ? LT_PRESENT_STICKER
                                                                      : LT_PRESENT_IMMERSIVE;
    out->covers_source = layout.covers_source ? 1 : 0;
    out->show_source = layout.show_source ? 1 : 0;
    out->text_red = layout.text_color.r;
    out->text_green = layout.text_color.g;
    out->text_blue = layout.text_color.b;
    out->fill_red = layout.fill_color.r;
    out->fill_green = layout.fill_color.g;
    out->fill_blue = layout.fill_color.b;
    return 1;
  } catch (...) {
    std::memset(out, 0, sizeof(*out));
    return 0;
  }
}

extern "C" int lenstrans_core_build_prompt(const char *text, const char *source_language,
                                             const char *target_language, char *out,
                                             size_t out_capacity) {
  if (!text || !target_language || !out || out_capacity == 0) return 0;
  out[0] = '\0';
  try {
    lenstrans::TranslateRequest request;
    request.text = text;
    request.src_lang = source_language && source_language[0] ? source_language : "auto";
    request.tgt_lang = target_language;
    copy_string(lenstrans::WrapQwenChat(lenstrans::BuildTranslatePrompt(request)), out, out_capacity);
    return out[0] != '\0' ? 1 : 0;
  } catch (...) {
    return 0;
  }
}
