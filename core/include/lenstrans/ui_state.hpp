#pragma once

#include "lenstrans/ocr_block.hpp"

namespace lenstrans {

enum class UiActivity { Hidden, Stopped, Active, Paused };
enum class UiPresentation { Overlay, Bilingual };
enum class UiInput { RightClick, LeftDoubleClick, Start, Stop, Pause, Resume, Hide, Show,
                     SetOverlay, SetBilingual };

struct UiState {
  UiActivity activity = UiActivity::Stopped;
  UiPresentation presentation = UiPresentation::Overlay;
};

struct UiTransition {
  UiState state;
  bool activity_changed = false;
  bool presentation_changed = false;
};

struct UiVisual {
  ColorRgb border{10, 132, 255};
  float editing_fill_alpha = 0.08f;
  bool show_resize_handles = true;
  bool show_corner_markers = false;
};

enum class UiAnchor { None, Move, N, S, E, W, NE, NW, SE, SW };

struct UiRect {
  float x = 0;
  float y = 0;
  float w = 0;
  float h = 0;
};

inline UiAnchor HitTestUiAnchor(float x, float y, float width, float height,
                                float handle, bool resize_handles) {
  if (x < 0 || y < 0 || x >= width || y >= height) return UiAnchor::None;
  if (!resize_handles) return UiAnchor::Move;
  const bool left = x < handle;
  const bool right = x >= width - handle;
  const bool top = y < handle;
  const bool bottom = y >= height - handle;
  if (top && left) return UiAnchor::NW;
  if (top && right) return UiAnchor::NE;
  if (bottom && left) return UiAnchor::SW;
  if (bottom && right) return UiAnchor::SE;
  if (top) return UiAnchor::N;
  if (bottom) return UiAnchor::S;
  if (left) return UiAnchor::W;
  if (right) return UiAnchor::E;
  return UiAnchor::Move;
}

// Coordinates use a top-left origin and positive-down y. Platform adapters only convert
// coordinates; anchor behavior and opposite-edge preservation remain identical.
inline UiRect ApplyUiDrag(UiRect start, UiAnchor anchor, float dx, float dy,
                          float min_width, float min_height) {
  UiRect out = start;
  switch (anchor) {
    case UiAnchor::Move: out.x += dx; out.y += dy; break;
    case UiAnchor::N: out.y += dy; out.h -= dy; break;
    case UiAnchor::S: out.h += dy; break;
    case UiAnchor::W: out.x += dx; out.w -= dx; break;
    case UiAnchor::E: out.w += dx; break;
    case UiAnchor::NE: out.y += dy; out.h -= dy; out.w += dx; break;
    case UiAnchor::NW: out.x += dx; out.w -= dx; out.y += dy; out.h -= dy; break;
    case UiAnchor::SE: out.w += dx; out.h += dy; break;
    case UiAnchor::SW: out.x += dx; out.w -= dx; out.h += dy; break;
    case UiAnchor::None: return start;
  }
  const float right = start.x + start.w;
  const float bottom = start.y + start.h;
  if (out.w < min_width) {
    out.w = min_width;
    if (anchor == UiAnchor::W || anchor == UiAnchor::NW || anchor == UiAnchor::SW)
      out.x = right - min_width;
  }
  if (out.h < min_height) {
    out.h = min_height;
    if (anchor == UiAnchor::N || anchor == UiAnchor::NE || anchor == UiAnchor::NW)
      out.y = bottom - min_height;
  }
  return out;
}

inline UiTransition ApplyUiInput(UiState current, UiInput input) {
  UiTransition result{current};
  switch (input) {
    case UiInput::RightClick:
      result.state.activity = current.activity == UiActivity::Active
                                  ? UiActivity::Stopped
                                  : UiActivity::Active;
      break;
    case UiInput::LeftDoubleClick:
      result.state.presentation = current.presentation == UiPresentation::Overlay
                                      ? UiPresentation::Bilingual
                                      : UiPresentation::Overlay;
      break;
    case UiInput::Start:
    case UiInput::Resume:
      result.state.activity = UiActivity::Active;
      break;
    case UiInput::Stop:
      result.state.activity = UiActivity::Stopped;
      break;
    case UiInput::Pause:
      if (current.activity == UiActivity::Active) result.state.activity = UiActivity::Paused;
      break;
    case UiInput::Hide:
      result.state.activity = UiActivity::Hidden;
      break;
    case UiInput::Show:
      if (current.activity == UiActivity::Hidden) result.state.activity = UiActivity::Stopped;
      break;
    case UiInput::SetOverlay:
      result.state.presentation = UiPresentation::Overlay;
      break;
    case UiInput::SetBilingual:
      result.state.presentation = UiPresentation::Bilingual;
      break;
  }
  result.activity_changed = result.state.activity != current.activity;
  result.presentation_changed = result.state.presentation != current.presentation;
  return result;
}

inline UiVisual ResolveUiVisual(const UiState& state) {
  UiVisual visual;
  switch (state.activity) {
    case UiActivity::Active:
      visual.border = state.presentation == UiPresentation::Bilingual
                          ? ColorRgb{255, 159, 10}
                          : ColorRgb{48, 209, 88};
      visual.editing_fill_alpha = 0.0f;
      visual.show_resize_handles = false;
      visual.show_corner_markers = true;
      break;
    case UiActivity::Paused:
      visual.border = {142, 142, 147};
      visual.editing_fill_alpha = 0.0f;
      visual.show_resize_handles = false;
      visual.show_corner_markers = true;
      break;
    case UiActivity::Hidden:
    case UiActivity::Stopped:
      visual.border = state.presentation == UiPresentation::Bilingual
                          ? ColorRgb{175, 82, 222}
                          : ColorRgb{10, 132, 255};
      visual.editing_fill_alpha = 0.08f;
      visual.show_resize_handles = true;
      visual.show_corner_markers = false;
      break;
  }
  return visual;
}

}  // namespace lenstrans
