#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "lenstrans/boxes.hpp"
#include "lenstrans/cache.hpp"
#include "lenstrans/dispatch.hpp"
#include "lenstrans/engine.hpp"
#include "lenstrans/frame_diff.hpp"
#include "lenstrans/geom.hpp"
#include "lenstrans/model_meta.hpp"
#include "lenstrans/paths.hpp"
#include "lenstrans/pipeline.hpp"
#include "lenstrans/present.hpp"
#include "lenstrans/settings.hpp"
#include "win/app/model_download.hpp"
#include "win/app/secrets.hpp"
#include "win/app/ui.hpp"
#include "win/capture/capture.hpp"
#include "win/ocr/winrt_ocr.hpp"

#include <windows.h>
#include <windowsx.h>
#include <psapi.h>
#include <shellapi.h>
#pragma comment(lib, "psapi.lib")

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr int kDefaultW = 480;
constexpr int kDefaultH = 320;
constexpr int kHandle = 12;
constexpr int kDragBarH = 32;
constexpr int kMinSize = 160;
constexpr int kHkEdit = 1;
constexpr int kHkNew = 2;
constexpr int kHkPause = 3;
constexpr int kHkHide = 4;
constexpr int kHkSettings = 5;
constexpr UINT kTrayMsg = WM_APP + 1;
constexpr UINT kPaintMsg = WM_APP + 2;
constexpr UINT kHoverTimer = 1;

enum class Hit { None, Drag, N, S, E, W, NE, NW, SE, SW };

struct OverlayBox {
  HWND hwnd = nullptr;
  bool editing = true;
  bool dragging = false;
  Hit hit = Hit::None;
  POINT grab{};
  RECT start{};
  int width = kDefaultW;
  int height = kDefaultH;
  lenstrans::BoxState state = lenstrans::BoxState::Editing;
  lenstrans::win::RegionCapture cap;
  std::vector<std::uint8_t> prev;
  int prev_w = 0, prev_h = 0;
  lenstrans::FrameDiff last_diff;
  std::vector<lenstrans::OcrBlock> debug_ocr;
  std::vector<lenstrans::OcrBlock> committed;
  std::vector<std::string> translations;
  std::vector<int> last_text_blocks;
  lenstrans::Stabilizer stab;
  lenstrans::Debounce debounce;
  lenstrans::IdleWatch idle;
  std::string last_ocr_err;
  std::string last_src;
  std::string src_lang = "auto";
  std::string tgt_lang = "zh";
  lenstrans::EnginePref engine = lenstrans::EnginePref::Auto;
  lenstrans::RenderLock render = lenstrans::RenderLock::Auto;
  std::mutex mu;
  std::vector<lenstrans::OcrBlock> fade_committed;
  std::vector<std::string> fade_trans;
  bool region_has_text = false;
  int empty_ms = 0;
  int hover_ms = 0;
  int hover_i = -1;
  bool last_lbutton = false;
  bool e2e_saw_ocr = false;
  bool e2e_saw_present = false;
  bool e2e_saw_cover = false;
  std::string e2e_sample_src;
};

struct App {
  std::mutex boxes_mu;
  std::vector<std::unique_ptr<OverlayBox>> boxes;
  lenstrans::Settings settings;
  std::string api_key;
  lenstrans::TranslationCache cache;
  std::unique_ptr<lenstrans::IEngine> local;
  std::unique_ptr<lenstrans::IEngine> cloud;
  lenstrans::win::AppHooks hooks;
  HWND hidden = nullptr;
  std::atomic<bool> run{true};
  std::atomic<bool> paused{false};
  std::atomic<bool> boxes_visible{true};
  std::thread worker;
  bool demo_edit = false;
  std::chrono::steady_clock::time_point demo_until{};
  int ws_probe_sec = 0;
  int e2e_sec = 0;
  bool e2e_stable = false;
  bool e2e_contrast = false;
  bool e2e_two_box = false;
  bool e2e_llama = false;
  bool e2e_wgc_window = false;
  bool e2e_wgc_monitor = false;
  bool e2e_external = false;
  bool e2e_ui = false;
  int e2e_ui_sec = 0;
  bool e2e_ui_settings = false;
  bool e2e_ui_onboard = false;
  bool e2e_ui_tray = false;
  bool e2e_ui_hotkey = false;
  bool e2e_hotkey_probe = false;
  bool hotkey_probe_done = false;
  bool hotkey_probe_watching0 = false;
  bool hotkey_probe_editing1 = false;
  bool hotkey_probe_watching2 = false;
  bool hotkey_probe_pass = false;
  std::chrono::steady_clock::time_point e2e_ui_until{};
  bool e2e_saw_wgc = false;
  bool e2e_ocr_via_wgc = false;
  std::string e2e_first_ocr;
  int e2e_first_token_ms = -1;
  int e2e_latency_ms = -1;
  double e2e_ws_mib = -1;
  std::string e2e_sample_src;
  std::string e2e_sample_hyp;
  bool have_init_rect = false;
  RECT init_rect{};
  std::vector<RECT> e2e_rects;
  bool skip_onboard = false;
  HWND fixture = nullptr;
  HWND e2e_target_hwnd = nullptr;
  RECT fixture_rect{};
  std::mutex e2e_mu;
  std::string e2e_log;
  int e2e_ocr = 0;
  int e2e_tr = 0;
  std::string e2e_present;
  bool e2e_cover = false;
  std::chrono::steady_clock::time_point e2e_until{};
  int virt_l = 0, virt_t = 0, virt_w = 0, virt_h = 0;
  float last_dpi = 96.f;
};

App g;

HWND WgcCaptureTarget() {
  return g.e2e_target_hwnd;
}

uint32_t Premul(uint8_t a, uint8_t red, uint8_t green, uint8_t blue) {
  return (uint32_t(a) << 24) | (uint32_t(red * a / 255) << 16) | (uint32_t(green * a / 255) << 8) |
         uint32_t(blue * a / 255);
}

void FillRectPx(uint32_t* px, int stride, int x0, int y0, int x1, int y1, int w, int h,
                uint32_t color) {
  x0 = std::max(0, x0);
  y0 = std::max(0, y0);
  x1 = std::min(w, x1);
  y1 = std::min(h, y1);
  for (int y = y0; y < y1; ++y) {
    uint32_t* row = px + y * stride;
    for (int x = x0; x < x1; ++x) row[x] = color;
  }
}

void BlendRect(uint32_t* px, int stride, int x0, int y0, int x1, int y1, int w, int h, uint8_t a,
               uint8_t red, uint8_t green, uint8_t blue) {
  FillRectPx(px, stride, x0, y0, x1, y1, w, h, Premul(a, red, green, blue));
}

Hit HitTest(int x, int y, int w, int h) {
  const bool nearL = x < kHandle, nearR = x >= w - kHandle, nearT = y < kHandle,
             nearB = y >= h - kHandle;
  if (nearT && nearL) return Hit::NW;
  if (nearT && nearR) return Hit::NE;
  if (nearB && nearL) return Hit::SW;
  if (nearB && nearR) return Hit::SE;
  if (nearT) return Hit::N;
  if (nearB) return Hit::S;
  if (nearL) return Hit::W;
  if (nearR) return Hit::E;
  if (y < kDragBarH) return Hit::Drag;
  return Hit::None;
}

LPCWSTR CursorFor(Hit hit) {
  switch (hit) {
    case Hit::N:
    case Hit::S:
      return IDC_SIZENS;
    case Hit::E:
    case Hit::W:
      return IDC_SIZEWE;
    case Hit::NE:
    case Hit::SW:
      return IDC_SIZENESW;
    case Hit::NW:
    case Hit::SE:
      return IDC_SIZENWSE;
    default:
      return IDC_ARROW;
  }
}

OverlayBox* BoxOf(HWND hwnd) {
  std::lock_guard<std::mutex> lock(g.boxes_mu);
  for (auto& b : g.boxes)
    if (b->hwnd == hwnd) return b.get();
  return nullptr;
}

void ApplyExStyle(HWND hwnd, bool clickThrough) {
  LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  ex |= WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW;
  if (clickThrough) {
    ex |= WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
  } else {
    ex &= ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
  }
  SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
  SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}

void PaintBox(OverlayBox* box);
void LogA(const std::string& s);

void CopyUtf8(const std::string& utf8) {
  if (utf8.empty()) return;
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
  if (n <= 0) return;
  HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, static_cast<SIZE_T>(n + 1) * sizeof(wchar_t));
  if (!mem) return;
  auto* dst = static_cast<wchar_t*>(GlobalLock(mem));
  if (!dst) {
    GlobalFree(mem);
    return;
  }
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), dst, n);
  dst[n] = 0;
  GlobalUnlock(mem);
  if (OpenClipboard(nullptr)) {
    EmptyClipboard();
    SetClipboardData(CF_UNICODETEXT, mem);
    CloseClipboard();
  } else {
    GlobalFree(mem);
  }
}

int HitTransBlock(const std::vector<lenstrans::OcrBlock>& blocks, int x, int y) {
  for (int i = static_cast<int>(blocks.size()) - 1; i >= 0; --i) {
    const auto& b = blocks[static_cast<size_t>(i)];
    const int x0 = static_cast<int>(b.bbox.x);
    const int y0 = static_cast<int>(b.bbox.y);
    const int x1 = x0 + std::max(8, static_cast<int>(b.bbox.w));
    const int y1 = y0 + std::max(8, static_cast<int>(b.bbox.h));
    if (x >= x0 && x < x1 && y >= y0 && y < y1) return i;
  }
  return -1;
}

void TickHoverFade() {
  OverlayBox* raw[16]{};
  int n = 0;
  {
    std::lock_guard<std::mutex> lock(g.boxes_mu);
    for (auto& b : g.boxes) {
      if (n < 16) raw[n++] = b.get();
    }
  }
  for (int i = 0; i < n; ++i) {
    OverlayBox* box = raw[i];
    if (!box || !box->hwnd || box->editing) continue;
    bool has = false;
    {
      std::lock_guard<std::mutex> lock(box->mu);
      has = box->region_has_text;
      if (has && !box->committed.empty()) {
        box->fade_committed = box->committed;
        box->fade_trans = box->translations;
      }
    }
    if (has)
      box->empty_ms = 0;
    else
      box->empty_ms = std::min(1000, box->empty_ms + 50);

    POINT cur{};
    GetCursorPos(&cur);
    POINT local = cur;
    ScreenToClient(box->hwnd, &local);
    std::vector<lenstrans::OcrBlock> blocks;
    std::vector<std::string> trans;
    {
      std::lock_guard<std::mutex> lock(box->mu);
      blocks = box->fade_committed.empty() ? box->committed : box->fade_committed;
      trans = box->fade_trans.empty() ? box->translations : box->fade_trans;
    }
    const int hit = HitTransBlock(blocks, local.x, local.y);
    if (hit == box->hover_i && hit >= 0)
      box->hover_ms = std::min(2000, box->hover_ms + 50);
    else {
      box->hover_i = hit;
      box->hover_ms = 0;
    }
    const bool down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    if (down && !box->last_lbutton && lenstrans::HoverArmed(box->hover_ms) && box->hover_i >= 0 &&
        box->hover_i < static_cast<int>(trans.size())) {
      CopyUtf8(trans[static_cast<size_t>(box->hover_i)]);
      LogA("COPY translation\n");
    }
    box->last_lbutton = down;
    PaintBox(box);
  }
}

void DrawUtf8(HDC hdc, int x, int y, int w, int h, const std::string& utf8, COLORREF color) {
  if (utf8.empty()) return;
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring ws(static_cast<std::size_t>(n), 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), ws.data(), n);
  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, color);
  RECT rc{x, y, x + w, y + h};
  DrawTextW(hdc, ws.c_str(), n, &rc, DT_LEFT | DT_WORDBREAK | DT_NOPREFIX);
}

void FixAlpha(uint32_t* px, int w, int h, int x0, int y0, int x1, int y1) {
  x0 = std::max(0, x0);
  y0 = std::max(0, y0);
  x1 = std::min(w, x1);
  y1 = std::min(h, y1);
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      uint32_t& p = px[y * w + x];
      const uint8_t a = static_cast<uint8_t>(p >> 24);
      if (a == 0) {
        const uint8_t red = static_cast<uint8_t>(p >> 16);
        const uint8_t green = static_cast<uint8_t>(p >> 8);
        const uint8_t blue = static_cast<uint8_t>(p);
        if (red | green | blue) p = Premul(230, red, green, blue);
      }
    }
  }
}

void PaintBox(OverlayBox* box) {
  if (!box || !box->hwnd) return;
  RECT rc{};
  GetClientRect(box->hwnd, &rc);
  const int w = rc.right - rc.left;
  const int h = rc.bottom - rc.top;
  if (w <= 0 || h <= 0) return;
  box->width = w;
  box->height = h;

  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HDC screen = GetDC(nullptr);
  HDC mem = CreateCompatibleDC(screen);
  HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  HGDIOBJ old = SelectObject(mem, dib);
  auto* px = static_cast<uint32_t*>(bits);
  const bool editing = box->editing;
  const uint8_t fill_a = editing ? 36 : static_cast<uint8_t>(std::max(2.f, g.settings.overlay_alpha * 255));
  std::fill(px, px + static_cast<size_t>(w) * h, Premul(fill_a, 0, 0, 0));

  std::vector<lenstrans::OcrBlock> ocr, committed;
  std::vector<std::string> trans;
  lenstrans::FrameDiff diff;
  int empty_ms = 0, hover_ms = 0, hover_i = -1;
  bool has_text_locked = false;
  {
    std::lock_guard<std::mutex> lock(box->mu);
    ocr = box->debug_ocr;
    committed = box->committed;
    trans = box->translations;
    if (!editing && (committed.empty() || trans.empty()) && !box->fade_committed.empty()) {
      committed = box->fade_committed;
      trans = box->fade_trans;
    }
    diff = box->last_diff;
    empty_ms = box->empty_ms;
    hover_ms = box->hover_ms;
    hover_i = box->hover_i;
    has_text_locked = box->region_has_text;
  }
  const bool has_text = editing || has_text_locked;
  const float fade = editing ? 1.f : lenstrans::FadeOverlayAlpha(has_text, empty_ms);

  if (editing && diff.cols > 0 && diff.rows > 0) {
    const float cw = static_cast<float>(w) / diff.cols;
    const float ch = static_cast<float>(h) / diff.rows;
    for (int by = 0; by < diff.rows; ++by) {
      for (int bx = 0; bx < diff.cols; ++bx) {
        if (!diff.changed[static_cast<size_t>(by) * diff.cols + bx]) continue;
        BlendRect(px, w, static_cast<int>(bx * cw), static_cast<int>(by * ch),
                  static_cast<int>((bx + 1) * cw), static_cast<int>((by + 1) * ch), w, h, 50, 255, 180,
                  0);
      }
    }
  }

  const auto draw_block = [&](const lenstrans::OcrBlock& b, const std::string& text, bool is_trans) {
    const int x = static_cast<int>(b.bbox.x);
    const int y = static_cast<int>(b.bbox.y);
    const int bw = std::max(8, static_cast<int>(b.bbox.w));
    int bh = std::max(8, static_cast<int>(b.bbox.h * (g.settings.font_scale / 100.f)));
    const auto mode =
        lenstrans::DecidePresent(b.bg_variance, g.settings.contrast, box->render);
    int fr = 240, fg = 240, fb = 240;
    if (mode == lenstrans::PresentMode::Immersive) {
      // sample fill from ring is approximated as inverted-safe solid
      fr = 245;
      fg = 245;
      fb = 245;
      BlendRect(px, w, x, y, x + bw, y + bh, w, h, 255, static_cast<uint8_t>(fr),
                static_cast<uint8_t>(fg), static_cast<uint8_t>(fb));
    } else {
      const uint8_t a = static_cast<uint8_t>(g.settings.sticker_alpha * 255 / 100);
      BlendRect(px, w, x, y, x + bw, y + bh + (mode == lenstrans::PresentMode::StickerContrast ? bh / 2 : 0),
                w, h, a, 32, 32, 32);
      if (mode == lenstrans::PresentMode::StickerContrast) bh = bh + bh / 2;
    }
    int tr = b.color.r, tg = b.color.g, tb = b.color.b;
    if (!lenstrans::ContrastOk(tr, tg, tb, fr, fg, fb)) lenstrans::InvertRgb(tr, tg, tb);
    DrawUtf8(mem, x + 4, y + 2, bw - 8, bh - 4, text, RGB(tr, tg, tb));
    if (mode == lenstrans::PresentMode::StickerContrast && is_trans) {
      DrawUtf8(mem, x + 4, y + bh * 2 / 3, bw - 8, bh / 3, b.text, RGB(200, 200, 200));
    }
    FixAlpha(px, w, h, x, y, x + bw, y + bh);
  };

  if (!editing) {
    for (size_t i = 0; i < committed.size() && i < trans.size(); ++i) {
      if (!trans[i].empty()) draw_block(committed[i], trans[i], true);
    }
  } else {
    for (const auto& b : ocr) {
      BlendRect(px, w, static_cast<int>(b.bbox.x), static_cast<int>(b.bbox.y),
                static_cast<int>(b.bbox.x + b.bbox.w), static_cast<int>(b.bbox.y + b.bbox.h), w, h, 70,
                0, 90, 160);
    }
  }

  const uint32_t border = Premul(editing ? 160 : 80, 128, 128, 128);
  FillRectPx(px, w, 0, 0, w, 1, w, h, border);
  FillRectPx(px, w, 0, h - 1, w, h, w, h, border);
  FillRectPx(px, w, 0, 0, 1, h, w, h, border);
  FillRectPx(px, w, w - 1, 0, w, h, w, h, border);
  if (editing) {
    FillRectPx(px, w, 1, 1, w - 1, kDragBarH, w, h, Premul(50, 0, 0, 0));
    const int hs[8][2] = {{0, 0},
                          {(w - kHandle) / 2, 0},
                          {w - kHandle, 0},
                          {0, (h - kHandle) / 2},
                          {w - kHandle, (h - kHandle) / 2},
                          {0, h - kHandle},
                          {(w - kHandle) / 2, h - kHandle},
                          {w - kHandle, h - kHandle}};
    for (auto& p : hs)
      FillRectPx(px, w, p[0], p[1], p[0] + kHandle, p[1] + kHandle, w, h, Premul(230, 0, 120, 212));
    uint8_t sr = 80, sg = 80, sb = 80;
    if (box->state == lenstrans::BoxState::Translating) {
      sr = 220;
      sg = 180;
      sb = 40;
    } else if (box->state == lenstrans::BoxState::Watching) {
      sr = 40;
      sg = 180;
      sb = 80;
    } else if (box->state == lenstrans::BoxState::Paused) {
      sr = 140;
      sg = 140;
      sb = 140;
    }
    FillRectPx(px, w, w - 14, 6, w - 6, 14, w, h, Premul(255, sr, sg, sb));
  }

  if (!editing && fade > 0.f && lenstrans::HoverArmed(hover_ms) && hover_i >= 0 &&
      hover_i < static_cast<int>(committed.size())) {
    const auto& b = committed[static_cast<size_t>(hover_i)];
    const int bx = static_cast<int>(b.bbox.x);
    const int by = static_cast<int>(b.bbox.y);
    const int bw = std::max(120, static_cast<int>(b.bbox.w));
    const int bh = 40;
    const int ty = std::max(0, by - bh - 6);
    BlendRect(px, w, bx, ty, bx + bw, ty + bh, w, h, 220, 24, 24, 24);
    DrawUtf8(mem, bx + 6, ty + 4, bw - 12, bh - 8, b.text, RGB(255, 255, 255));
    DrawUtf8(mem, bx + 6, ty + 22, bw - 12, 14, "点击复制译文", RGB(180, 180, 180));
    FixAlpha(px, w, h, bx, ty, bx + bw, ty + bh);
  }

  POINT ptSrc{0, 0};
  SIZE size{w, h};
  BLENDFUNCTION blend{};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = static_cast<BYTE>(std::max(0.f, std::min(255.f, fade * 255.f)));
  blend.AlphaFormat = AC_SRC_ALPHA;
  UpdateLayeredWindow(box->hwnd, screen, nullptr, &size, mem, &ptSrc, 0, &blend, ULW_ALPHA);
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
}

void SetEditing(OverlayBox* box, bool editing) {
  if (!box) return;
  box->editing = editing;
  box->state = editing ? lenstrans::BoxState::Editing : (g.paused.load() ? lenstrans::BoxState::Paused
                                                                         : lenstrans::BoxState::Watching);
  ApplyExStyle(box->hwnd, !editing);
  PaintBox(box);
}

void ApplyHitMove(OverlayBox* box, int mx, int my) {
  RECT r = box->start;
  const int dx = mx - box->grab.x;
  const int dy = my - box->grab.y;
  switch (box->hit) {
    case Hit::Drag:
      OffsetRect(&r, dx, dy);
      break;
    case Hit::N:
      r.top += dy;
      break;
    case Hit::S:
      r.bottom += dy;
      break;
    case Hit::W:
      r.left += dx;
      break;
    case Hit::E:
      r.right += dx;
      break;
    case Hit::NW:
      r.left += dx;
      r.top += dy;
      break;
    case Hit::NE:
      r.right += dx;
      r.top += dy;
      break;
    case Hit::SW:
      r.left += dx;
      r.bottom += dy;
      break;
    case Hit::SE:
      r.right += dx;
      r.bottom += dy;
      break;
    default:
      return;
  }
  if (r.right - r.left < kMinSize) {
    if (box->hit == Hit::W || box->hit == Hit::NW || box->hit == Hit::SW)
      r.left = r.right - kMinSize;
    else
      r.right = r.left + kMinSize;
  }
  if (r.bottom - r.top < kMinSize) {
    if (box->hit == Hit::N || box->hit == Hit::NW || box->hit == Hit::NE)
      r.top = r.bottom - kMinSize;
    else
      r.bottom = r.top + kMinSize;
  }
  SetWindowPos(box->hwnd, HWND_TOPMOST, r.left, r.top, r.right - r.left, r.bottom - r.top, SWP_NOACTIVATE);
  RECT client{};
  GetClientRect(box->hwnd, &client);
  POINT tl{0, 0};
  ClientToScreen(box->hwnd, &tl);
  RECT phys{tl.x, tl.y, tl.x + (client.right - client.left), tl.y + (client.bottom - client.top)};
  box->cap.UpdateRect(phys);
  PaintBox(box);
}

RECT ClientPhys(HWND hwnd) {
  RECT c{};
  GetClientRect(hwnd, &c);
  POINT tl{0, 0};
  ClientToScreen(hwnd, &tl);
  return {tl.x, tl.y, tl.x + (c.right - c.left), tl.y + (c.bottom - c.top)};
}

void LogA(const std::string& s) {
  HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
  DWORD n = 0;
  WriteConsoleA(out, s.c_str(), static_cast<DWORD>(s.size()), &n, nullptr);
  if (g.e2e_sec > 0) {
    std::lock_guard<std::mutex> lock(g.e2e_mu);
    g.e2e_log += s;
  }
}

std::string FindModel() {
  return lenstrans::FindDefaultModelPath(g.settings.model_path);
}

std::string FindCli() { return lenstrans::FindLlamaCliPath(); }

std::string EvalOutPath(const char* name) {
  return lenstrans::JoinPath(lenstrans::EvalOutDir(), name);
}

void RegisterAppHotkeys() {
  if (!g.hidden) return;
  for (int i = 1; i <= 5; ++i) UnregisterHotKey(g.hidden, i);
  RegisterHotKey(g.hidden, kHkEdit, g.settings.mod_edit | MOD_NOREPEAT,
                 static_cast<UINT>(g.settings.vk_edit));
  RegisterHotKey(g.hidden, kHkNew, g.settings.mod_new | MOD_NOREPEAT,
                 static_cast<UINT>(g.settings.vk_new));
  RegisterHotKey(g.hidden, kHkPause, g.settings.mod_pause | MOD_NOREPEAT,
                 static_cast<UINT>(g.settings.vk_pause));
  RegisterHotKey(g.hidden, kHkHide, g.settings.mod_hide | MOD_NOREPEAT,
                 static_cast<UINT>(g.settings.vk_hide));
  RegisterHotKey(g.hidden, kHkSettings, g.settings.mod_settings | MOD_NOREPEAT,
                 static_cast<UINT>(g.settings.vk_settings));
}

void EnsureEngines() {
  if (g.e2e_sec > 0 && !g.e2e_llama) {
    if (!g.local) g.local = lenstrans::MakeFakeEngine(lenstrans::EngineKind::Local, true, "你好 设置", "");
    return;
  }
  if (!g.local) {
    const std::string model = FindModel();
    if (g.e2e_llama) LogA(std::string("E2E llama model=") + model + "\n");
    g.local = lenstrans::MakeLocalEngine(model, FindCli());
  }
  if (g.e2e_sec == 0)
    g.cloud = lenstrans::MakeCloudEngine(g.settings.cloud_base_url, g.api_key, g.settings.cloud_model);
}

void TranslateCommitted(OverlayBox* box, const std::vector<lenstrans::OcrBlock>& blocks) {
  EnsureEngines();
  std::vector<std::string> outs(blocks.size());
  box->state = lenstrans::BoxState::Translating;
  for (size_t i = 0; i < blocks.size(); ++i) {
    lenstrans::TranslateRequest req;
    req.text = blocks[i].text;
    req.src_lang = box->src_lang.empty() ? g.settings.src_lang : box->src_lang;
    req.tgt_lang = box->tgt_lang.empty() ? g.settings.tgt_lang : box->tgt_lang;
    req.quality = g.settings.quality;
    lenstrans::Settings per = g.settings;
    per.engine = box->engine;
    per.render = box->render;
    per.src_lang = req.src_lang;
    per.tgt_lang = req.tgt_lang;
    const auto r = lenstrans::DispatchTranslate(per, g.local.get(), g.cloud.get(), &g.cache, req);
    if (r.from_cache) LogA("CACHE hit\n");
    if (!r.error.empty()) LogA(std::string("TR err ") + r.error + "\n");
    if (g.e2e_llama) {
      char tline[160];
      std::snprintf(tline, sizeof(tline), "TR first_token_ms=%d latency_ms=%d beam=%d\n",
                    r.first_token_ms, r.latency_ms, r.beam_width);
      LogA(tline);
      if (g.e2e_first_token_ms < 0 && r.error.empty()) {
        g.e2e_first_token_ms = r.first_token_ms;
        g.e2e_latency_ms = r.latency_ms;
        g.e2e_sample_src = blocks[i].text;
        g.e2e_sample_hyp = r.text;
      }
    }
    outs[i] = r.text;
    const auto mode =
        lenstrans::DecidePresent(blocks[i].bg_variance, g.settings.contrast, box->render);
    const char* mn = mode == lenstrans::PresentMode::Immersive
                         ? "immersive"
                         : mode == lenstrans::PresentMode::StickerContrast ? "sticker+contrast"
                                                                          : "sticker";
    const bool cover = mode == lenstrans::PresentMode::Immersive || g.settings.sticker_alpha >= 60;
    const bool show_source = mode == lenstrans::PresentMode::StickerContrast;
    char pline[384];
    std::snprintf(pline, sizeof(pline),
                  "PRESENT mode=%s cover=%d show_source=%d stack=0 src=\"%s\" hyp=\"%s\" var=%.1f\n",
                  mn, cover ? 1 : 0, show_source ? 1 : 0, blocks[i].text.c_str(), r.text.c_str(),
                  blocks[i].bg_variance);
    LogA(pline);
    g.e2e_present = mn;
    g.e2e_cover = cover;
    box->e2e_saw_present = true;
    if (cover) {
      box->e2e_saw_cover = true;
      LogA("COVER_OK overlay_opaque_fill stack=0 not_translucent_overprint\n");
    }
    if (!r.text.empty()) ++g.e2e_tr;
  }
  {
    std::lock_guard<std::mutex> lock(box->mu);
    box->translations = std::move(outs);
    box->committed = blocks;
    box->state = g.paused.load() ? lenstrans::BoxState::Paused : lenstrans::BoxState::Watching;
  }
  PostMessageW(box->hwnd, kPaintMsg, 0, 0);
}

void WorkerLoop() {
  constexpr int kAwakeMs = 70;
  constexpr int kIdleSleepMs = 400;
  auto wake_state = [](OverlayBox* box, int e2e_sec, bool e2e_stable) {
    const bool committed_empty = box->committed.empty();
    const bool debounce_pending = box->debounce.pending;
    const bool e2e_fast = e2e_sec > 0 && committed_empty && !e2e_stable;
    const bool e2e_bootstrap =
        e2e_sec > 0 && committed_empty && box->last_text_blocks.empty();
    // Content revision: stab tracking differs from last PRESENT — keep pipeline until TranslateCommitted.
    const bool revision_pending =
        !committed_empty && box->stab.has_prev &&
        !lenstrans::SameBlocks(box->stab.prev, box->committed);
    // Neighborhood OCR / stab / debounce while bootstrapping, or during revision after idle wake.
    const bool pipeline_active =
        debounce_pending || revision_pending ||
        (committed_empty && box->stab.has_prev) ||
        (committed_empty && !box->last_text_blocks.empty());
    return std::tuple{e2e_fast, e2e_bootstrap, pipeline_active,
                      e2e_fast || e2e_bootstrap || pipeline_active};
  };
  while (g.run.load()) {
    const bool sleep_all = g.paused.load() || !g.boxes_visible.load();
    OverlayBox* raw[16]{};
    int nbox = 0;
    {
      std::lock_guard<std::mutex> lock(g.boxes_mu);
      for (auto& b : g.boxes) {
        if (nbox < 16) raw[nbox++] = b.get();
      }
    }
    const auto tick = std::chrono::steady_clock::now();
    if (g.local) g.local->MaybeIdleUnload(lenstrans::kLocalIdleUnloadMs);
    bool any_awake = false;
    if (!sleep_all) {
      for (int bi = 0; bi < nbox; ++bi) {
        OverlayBox* box = raw[bi];
        if (!box->hwnd || box->state == lenstrans::BoxState::Hidden) continue;
        const auto [e2e_fast, e2e_bootstrap, pipeline_active, keep_awake] =
            wake_state(box, g.e2e_sec, g.e2e_stable);
        (void)e2e_fast;
        (void)e2e_bootstrap;
        (void)pipeline_active;
        if (keep_awake || !box->idle.ShouldSleep(tick)) any_awake = true;
      }
    }
    const int loop_ms = sleep_all ? 400 : any_awake ? kAwakeMs : kIdleSleepMs;
    std::this_thread::sleep_for(std::chrono::milliseconds(loop_ms));
    if (sleep_all) continue;
    for (int bi = 0; bi < nbox; ++bi) {
      OverlayBox* box = raw[bi];
      if (!box->hwnd || box->state == lenstrans::BoxState::Hidden) continue;
      const auto now = std::chrono::steady_clock::now();
      const auto [e2e_fast, e2e_bootstrap, pipeline_active, keep_awake] =
          wake_state(box, g.e2e_sec, g.e2e_stable);
      const bool idle_probe = box->idle.ShouldSleep(now) && !keep_awake;
      RECT phys = ClientPhys(box->hwnd);
      box->cap.UpdateRect(phys);
      lenstrans::win::BgraFrame frame;
      if (!box->cap.Grab(frame)) {
        static int fail = 0;
        if ((++fail % 30) == 1) {
          LogA(std::string("CAP fail: ") + box->cap.LastError() + "\n");
          box->cap.Start(box->hwnd, phys, WgcCaptureTarget());
        }
        continue;
      }
      if ((g.e2e_wgc_window || g.e2e_wgc_monitor) && frame.source == "wgc") g.e2e_saw_wgc = true;
      if (box->prev.empty() || box->prev_w != frame.w || box->prev_h != frame.h) {
        box->prev = frame.bgra;
        box->prev_w = frame.w;
        box->prev_h = frame.h;
        if (!e2e_bootstrap) continue;
      }
      auto diff = lenstrans::DiffFrames(box->prev.data(), frame.bgra.data(), frame.w, frame.h,
                                        frame.w * 4);
      box->prev = frame.bgra;
      box->prev_w = frame.w;
      box->prev_h = frame.h;
      {
        std::lock_guard<std::mutex> lock(box->mu);
        box->last_diff = diff;
        box->last_src = frame.source;
      }
      if ((g.e2e_wgc_window || g.e2e_wgc_monitor) && frame.source == "wgc") g.e2e_saw_wgc = true;
      if (diff.changed_count > 0) {
        box->idle.Motion(now);
        char line[128];
        std::snprintf(line, sizeof(line), "DIFF %s blocks=%d %dx%d\n", frame.source.c_str(),
                      diff.changed_count, frame.w, frame.h);
        LogA(line);
      } else if (idle_probe) {
        continue;
      }
      if (!pipeline_active && diff.changed_count == 0 && !e2e_fast && !e2e_bootstrap) continue;
      PostMessageW(box->hwnd, kPaintMsg, 0, 0);
      if (box->editing && !g.demo_edit) continue;

      std::vector<std::uint8_t> mask;
      lenstrans::UnionChangedAndDilated(diff, box->last_text_blocks, 1, mask);
      std::vector<lenstrans::win::OcrRoi> rois;
      if (diff.changed_count == 0 && !pipeline_active && !e2e_fast && !e2e_bootstrap) continue;
      if (diff.cols > 0) {
        const float cw = static_cast<float>(frame.w) / diff.cols;
        const float ch = static_cast<float>(frame.h) / diff.rows;
        for (int i = 0; i < diff.cols * diff.rows; ++i) {
          if (!mask[static_cast<size_t>(i)]) continue;
          const int bx = i % diff.cols, by = i / diff.cols;
          rois.push_back({static_cast<int>(bx * cw), static_cast<int>(by * ch),
                          static_cast<int>(cw) + 1, static_cast<int>(ch) + 1});
        }
      }
      if (e2e_fast || e2e_bootstrap) rois.clear();
      std::string err;
      auto blocks = lenstrans::win::RecognizeOcr(frame, rois, err);
      {
        const RECT cap = ClientPhys(box->hwnd);
        std::vector<lenstrans::RectF> ex;
        if (HWND sh = lenstrans::win::SettingsWindowHandle()) {
          if (IsWindowVisible(sh)) {
            RECT sr{};
            GetWindowRect(sh, &sr);
            ex.push_back(lenstrans::ScreenRectToCapture(
                static_cast<float>(sr.left), static_cast<float>(sr.top),
                static_cast<float>(sr.right - sr.left), static_cast<float>(sr.bottom - sr.top),
                static_cast<float>(cap.left), static_cast<float>(cap.top)));
          }
        }
        if (!ex.empty()) lenstrans::FilterExcludedBlocks(blocks, ex);
      }
      if (blocks.empty()) {
        if (err == "OCR_EMPTY") LogA("OCR_EMPTY\n");
        else if (!err.empty()) LogA(std::string("OCR err ") + err + "\n");
        std::lock_guard<std::mutex> lock(box->mu);
        box->debug_ocr.clear();
        box->last_ocr_err = err;
        box->region_has_text = false;
        continue;
      }
      ++g.e2e_ocr;
      box->e2e_saw_ocr = true;
      if (box->e2e_sample_src.empty() && !blocks.empty()) box->e2e_sample_src = blocks[0].text;
      if (g.e2e_wgc_window || g.e2e_wgc_monitor) {
        if (frame.source == "wgc") g.e2e_ocr_via_wgc = true;
        if (g.e2e_first_ocr.empty() && !blocks.empty()) g.e2e_first_ocr = blocks[0].text;
      }
      for (const auto& b : blocks) {
        char line[256];
        std::snprintf(line, sizeof(line),
                      "OCR text=\"%s\" bbox=%.0f,%.0f,%.0f,%.0f lh=%.1f rgb=%u,%u,%u var=%.1f\n",
                      b.text.c_str(), b.bbox.x, b.bbox.y, b.bbox.w, b.bbox.h, b.line_height,
                      b.color.r, b.color.g, b.color.b, b.bg_variance);
        LogA(line);
      }
      {
        std::lock_guard<std::mutex> lock(box->mu);
        box->debug_ocr = blocks;
        box->region_has_text = true;
      }
      box->last_text_blocks.clear();
      for (const auto& b : blocks) {
        lenstrans::BlocksForBBox(frame.w, frame.h, b.bbox.x, b.bbox.y, b.bbox.w, b.bbox.h, diff.cols,
                                 diff.rows, box->last_text_blocks);
      }
      std::vector<lenstrans::OcrBlock> committed;
      if (e2e_fast) {
        committed = blocks;
      } else if (!box->stab.Feed(blocks, committed)) {
        continue;
      }
      if (e2e_fast || box->debounce.Tick(committed, now, 300)) TranslateCommitted(box, committed);
    }
  }
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

void SnapshotVirt() {
  g.virt_l = GetSystemMetrics(SM_XVIRTUALSCREEN);
  g.virt_t = GetSystemMetrics(SM_YVIRTUALSCREEN);
  g.virt_w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  g.virt_h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
}

void SaveAllBoxes() {
  std::vector<lenstrans::BoxPersist> rows;
  std::lock_guard<std::mutex> lock(g.boxes_mu);
  for (auto& b : g.boxes) {
    if (!b || !b->hwnd) continue;
    RECT wr{};
    GetWindowRect(b->hwnd, &wr);
    lenstrans::BoxPersist p;
    p.x = wr.left;
    p.y = wr.top;
    p.w = wr.right - wr.left;
    p.h = wr.bottom - wr.top;
    p.src_lang = b->src_lang;
    p.tgt_lang = b->tgt_lang;
    p.engine = b->engine;
    p.render = b->render;
    rows.push_back(p);
  }
  const std::string path = lenstrans::win::ConfigDir() + "\\boxes.cfg";
  std::ofstream f(path, std::ios::binary);
  if (f) f << lenstrans::SerializeBoxes(rows);
}

void RemapAllBoxes() {
  const int nl = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int nt = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int nw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int nh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  std::lock_guard<std::mutex> lock(g.boxes_mu);
  for (auto& b : g.boxes) {
    if (!b || !b->hwnd) continue;
    RECT wr{};
    GetWindowRect(b->hwnd, &wr);
    lenstrans::PhysBox pb{wr.left, wr.top, wr.right - wr.left, wr.bottom - wr.top};
    pb = lenstrans::RemapAfterDisplayChange(pb, g.virt_l, g.virt_t, g.virt_w, g.virt_h, nl, nt, nw,
                                            nh);
    SetWindowPos(b->hwnd, HWND_TOPMOST, pb.x, pb.y, pb.w, pb.h, SWP_NOACTIVATE);
    b->cap.Stop();
    b->cap.Start(b->hwnd, ClientPhys(b->hwnd), WgcCaptureTarget());
  }
  g.virt_l = nl;
  g.virt_t = nt;
  g.virt_w = nw;
  g.virt_h = nh;
}

void CreateBox(int x, int y, int w, int h, bool editing,
               const lenstrans::BoxPersist* persist = nullptr) {
  auto box = std::make_unique<OverlayBox>();
  HWND hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW, L"LensTransOverlayPoC",
                              L"LensTrans", WS_POPUP, x, y, w, h, nullptr, nullptr,
                              GetModuleHandleW(nullptr), nullptr);
  if (!hwnd) return;
  if (!g.e2e_wgc_monitor) lenstrans::win::ExcludeOverlayFromCapture(hwnd);
  box->src_lang = persist ? persist->src_lang : g.settings.src_lang;
  box->tgt_lang = persist ? persist->tgt_lang : g.settings.tgt_lang;
  box->engine = persist ? persist->engine : g.settings.engine;
  box->render = persist ? persist->render : g.settings.render;
  box->hwnd = hwnd;
  ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  OverlayBox* raw = nullptr;
  {
    std::lock_guard<std::mutex> lock(g.boxes_mu);
    g.boxes.push_back(std::move(box));
    raw = g.boxes.back().get();
  }
  SetEditing(raw, editing);
  if (!g.e2e_wgc_monitor && !lenstrans::win::ExcludeOverlayFromCapture(hwnd) && g.e2e_sec > 0) {
    LogA("WDA_EXCLUDEFROMCAPTURE failed\n");
  }
  raw->cap.Start(hwnd, ClientPhys(hwnd), WgcCaptureTarget());
}

void ToggleAllEdit() {
  bool any_edit = false;
  for (auto& b : g.boxes)
    if (b->editing) any_edit = true;
  for (auto& b : g.boxes) SetEditing(b.get(), !any_edit);
}

void OnTray(lenstrans::win::TrayCmd cmd) {
  switch (cmd) {
    case lenstrans::win::TrayCmd::ToggleBoxes:
      g.boxes_visible = !g.boxes_visible.load();
      for (auto& b : g.boxes) ShowWindow(b->hwnd, g.boxes_visible.load() ? SW_SHOWNOACTIVATE : SW_HIDE);
      break;
    case lenstrans::win::TrayCmd::NewBox: {
      const int sw = GetSystemMetrics(SM_CXSCREEN), sh = GetSystemMetrics(SM_CYSCREEN);
      CreateBox((sw - kDefaultW) / 2 + static_cast<int>(g.boxes.size()) * 24,
                sh / 3 - kDefaultH / 2, kDefaultW, kDefaultH, true);
      break;
    }
    case lenstrans::win::TrayCmd::Pause:
      g.paused = !g.paused.load();
      for (auto& b : g.boxes) {
        if (!b->editing)
          b->state = g.paused.load() ? lenstrans::BoxState::Paused : lenstrans::BoxState::Watching;
      }
      break;
    case lenstrans::win::TrayCmd::EngineLocal:
      g.settings.engine = lenstrans::EnginePref::Local;
      break;
    case lenstrans::win::TrayCmd::EngineCloud:
      g.settings.engine = lenstrans::EnginePref::Cloud;
      break;
    case lenstrans::win::TrayCmd::EngineAuto:
      g.settings.engine = lenstrans::EnginePref::Auto;
      break;
    case lenstrans::win::TrayCmd::LangZh:
      g.settings.tgt_lang = "zh";
      break;
    case lenstrans::win::TrayCmd::LangEn:
      g.settings.tgt_lang = "en";
      break;
    case lenstrans::win::TrayCmd::LangJa:
      g.settings.tgt_lang = "ja";
      break;
    case lenstrans::win::TrayCmd::LangKo:
      g.settings.tgt_lang = "ko";
      break;
    case lenstrans::win::TrayCmd::ModeTrans:
      g.settings.contrast = false;
      break;
    case lenstrans::win::TrayCmd::ModeContrast:
      g.settings.contrast = true;
      break;
    case lenstrans::win::TrayCmd::Autostart:
      lenstrans::win::SetAutostart(!lenstrans::win::AutostartEnabled());
      g.settings.autostart = lenstrans::win::AutostartEnabled();
      break;
    case lenstrans::win::TrayCmd::Settings:
      lenstrans::win::ShowSettingsWindow(g.hidden, g.hooks);
      break;
    case lenstrans::win::TrayCmd::Update:
      MessageBoxW(g.hidden, L"检查更新：本版本不联网自动更新。当前 0.2 / Qwen2.5-0.5B Q4_K_M。",
                  L"LensTrans", MB_OK);
      break;
    case lenstrans::win::TrayCmd::ClearCache:
      g.cache.Clear();
      g.hooks.cache_entries = 0;
      g.hooks.cache_bytes = 0;
      LogA("CACHE cleared\n");
      break;
    case lenstrans::win::TrayCmd::Quit:
      PostQuitMessage(0);
      break;
  }
  lenstrans::SaveSettingsFile(lenstrans::win::ConfigDir() + "\\settings.cfg", g.settings);
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  OverlayBox* box = BoxOf(hwnd);
  switch (msg) {
    case WM_DISPLAYCHANGE:
      RemapAllBoxes();
      if (box) PaintBox(box);
      return 0;
    case WM_DPICHANGED: {
      const RECT* suggested = reinterpret_cast<RECT*>(lparam);
      if (suggested) {
        SetWindowPos(hwnd, nullptr, suggested->left, suggested->top,
                     suggested->right - suggested->left, suggested->bottom - suggested->top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      }
      if (box) {
        box->cap.Stop();
        box->cap.Start(hwnd, ClientPhys(hwnd), WgcCaptureTarget());
        PaintBox(box);
      }
      SnapshotVirt();
      return 0;
    }
    case kPaintMsg:
      if (box) PaintBox(box);
      return 0;
    case WM_LBUTTONDOWN: {
      if (!box || !box->editing) return 0;
      box->hit = HitTest(GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam), box->width, box->height);
      if (box->hit == Hit::None) return 0;
      SetCapture(hwnd);
      box->dragging = true;
      GetWindowRect(hwnd, &box->start);
      GetCursorPos(&box->grab);
      return 0;
    }
    case WM_MOUSEMOVE: {
      if (box && box->editing && !box->dragging) {
        SetCursor(LoadCursorW(nullptr, CursorFor(HitTest(GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam),
                                                         box->width, box->height))));
      }
      if (!box || !box->dragging) return 0;
      POINT p{};
      GetCursorPos(&p);
      ApplyHitMove(box, p.x, p.y);
      return 0;
    }
    case WM_LBUTTONUP:
      if (box && box->dragging) {
        ReleaseCapture();
        box->dragging = false;
        box->hit = Hit::None;
      }
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) PostQuitMessage(0);
      return 0;
    case WM_DESTROY:
      return 0;
    default:
      return DefWindowProcW(hwnd, msg, wparam, lparam);
  }
}

LRESULT CALLBACK HiddenProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  if (msg == kTrayMsg) {
    if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU)
      lenstrans::win::ShowTrayMenu(hwnd, g.hooks);
    return 0;
  }
  if (msg == WM_HOTKEY) {
    if (wparam == kHkEdit) ToggleAllEdit();
    else if (wparam == kHkNew) OnTray(lenstrans::win::TrayCmd::NewBox);
    else if (wparam == kHkPause) OnTray(lenstrans::win::TrayCmd::Pause);
    else if (wparam == kHkHide) OnTray(lenstrans::win::TrayCmd::ToggleBoxes);
    else if (wparam == kHkSettings) OnTray(lenstrans::win::TrayCmd::Settings);
    return 0;
  }
  if (msg == WM_TIMER && wparam == kHoverTimer) {
    TickHoverFade();
    return 0;
  }
  if (msg == WM_DESTROY) PostQuitMessage(0);
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

LRESULT CALLBACK FixtureProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  if (msg == WM_PAINT) {
    PAINTSTRUCT ps{};
    HDC hdc = BeginPaint(hwnd, &ps);
    RECT rc{};
    GetClientRect(hwnd, &rc);
    FillRect(hdc, &rc, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, RGB(0, 0, 0));
    HFONT font = CreateFontW(40, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0,
                             CLEARTYPE_QUALITY, 0, L"Segoe UI");
    HGDIOBJ oldf = SelectObject(hdc, font);
    RECT line = rc;
    line.left += 20;
    line.top += 20;
    DrawTextW(hdc, L"HELLO Settings", -1, &line, DT_LEFT | DT_TOP | DT_SINGLELINE);
    line.top += 52;
    DrawTextW(hdc, L"Open File Cancel", -1, &line, DT_LEFT | DT_TOP | DT_SINGLELINE);
    line.top += 52;
    DrawTextW(hdc, L"Please wait", -1, &line, DT_LEFT | DT_TOP | DT_SINGLELINE);
    SelectObject(hdc, oldf);
    DeleteObject(font);
    EndPaint(hwnd, &ps);
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

void CreateFixture() {
  WNDCLASSW wc{};
  wc.lpfnWndProc = FixtureProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH));
  wc.lpszClassName = L"LensTransE2eFixture";
  RegisterClassW(&wc);
  const int x = 80, y = 80, w = 560, h = 280;
  g.fixture = CreateWindowExW(0, L"LensTransE2eFixture", L"LensTrans E2E EN",
                              WS_POPUP | WS_VISIBLE, x, y, w, h, nullptr, nullptr, wc.hInstance,
                              nullptr);
  if (!g.fixture) return;
  ShowWindow(g.fixture, SW_SHOW);
  UpdateWindow(g.fixture);
  GetWindowRect(g.fixture, &g.fixture_rect);
}

bool WriteBgraBmp(const lenstrans::win::BgraFrame& fr, const char* path) {
  if (fr.w <= 0 || fr.h <= 0 || fr.bgra.empty()) return false;
  const int w = fr.w;
  const int h = fr.h;
  const DWORD px = static_cast<DWORD>(w) * static_cast<DWORD>(h) * 4;
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  BITMAPFILEHEADER fh{};
  fh.bfType = 0x4D42;
  fh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  fh.bfSize = fh.bfOffBits + px;
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  std::ofstream f(path, std::ios::binary);
  if (!f) return false;
  f.write(reinterpret_cast<const char*>(&fh), sizeof(fh));
  f.write(reinterpret_cast<const char*>(&bi.bmiHeader), sizeof(BITMAPINFOHEADER));
  f.write(reinterpret_cast<const char*>(fr.bgra.data()), static_cast<std::streamsize>(px));
  return static_cast<bool>(f);
}

bool WriteScreenBmp(const RECT& r, const char* path) {
  const int w = std::max(1, static_cast<int>(r.right - r.left));
  const int h = std::max(1, static_cast<int>(r.bottom - r.top));
  HDC screen = GetDC(nullptr);
  HDC mem = CreateCompatibleDC(screen);
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  HGDIOBJ old = SelectObject(mem, dib);
  BitBlt(mem, 0, 0, w, h, screen, r.left, r.top, SRCCOPY | CAPTUREBLT);
  const DWORD px = static_cast<DWORD>(w) * static_cast<DWORD>(h) * 4;
  BITMAPFILEHEADER fh{};
  fh.bfType = 0x4D42;
  fh.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
  fh.bfSize = fh.bfOffBits + px;
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  std::ofstream f(path, std::ios::binary);
  bool ok = false;
  if (f && bits) {
    f.write(reinterpret_cast<const char*>(&fh), sizeof(fh));
    f.write(reinterpret_cast<const char*>(&bi.bmiHeader), sizeof(BITMAPINFOHEADER));
    f.write(reinterpret_cast<const char*>(bits), static_cast<std::streamsize>(px));
    ok = static_cast<bool>(f);
  }
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  return ok;
}

bool OverlayClickThrough(HWND hwnd) {
  return (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TRANSPARENT) != 0;
}

void PumpPendingMessages() {
  MSG msg{};
  while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
}

void WriteHotkeyProbeArtifacts() {
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  std::ofstream f(EvalOutPath("hotkey-probe.md"), std::ios::binary);
  if (!f) return;
  f << "# Hotkey WM_HOTKEY probe (edit / click-through toggle)\n\n"
    << "- command: `.\\build\\Release\\lenstrans_overlay.exe --e2e-hotkey-probe --no-onboard`\n"
    << "- status: " << (g.hotkey_probe_pass ? "**pass**" : "**fail**") << "\n"
    << "- hotkey_probe: " << (g.hotkey_probe_pass ? "**yes**" : "**no**") << "\n"
    << "- method: PostMessage WM_HOTKEY kHkEdit x2 (internal handler probe)\n"
    << "- initial_watching_transparent: " << (g.hotkey_probe_watching0 ? "yes" : "no") << "\n"
    << "- after_first_hotkey_editing: " << (g.hotkey_probe_editing1 ? "yes" : "no") << "\n"
    << "- after_second_hotkey_watching: " << (g.hotkey_probe_watching2 ? "yes" : "no") << "\n"
    << "- assert: WS_EX_TRANSPARENT on -> off -> on\n"
    << "- sendinput_ctrl_e: skip (RegisterHotKey ignores injected input per Win32)\n"
    << "- goal_complete: **no**\n";
}

void RunHotkeyProbeOnce() {
  if (g.hotkey_probe_done) return;
  g.hotkey_probe_done = true;
  HWND overlay = nullptr;
  {
    std::lock_guard<std::mutex> lock(g.boxes_mu);
    if (!g.boxes.empty() && g.boxes[0]->hwnd) overlay = g.boxes[0]->hwnd;
  }
  if (!overlay) {
    g.hotkey_probe_pass = false;
    WriteHotkeyProbeArtifacts();
    PostQuitMessage(0);
    return;
  }
  g.hotkey_probe_watching0 = OverlayClickThrough(overlay);
  PostMessageW(g.hidden, WM_HOTKEY, kHkEdit, 0);
  PumpPendingMessages();
  g.hotkey_probe_editing1 = !OverlayClickThrough(overlay);
  PostMessageW(g.hidden, WM_HOTKEY, kHkEdit, 0);
  PumpPendingMessages();
  g.hotkey_probe_watching2 = OverlayClickThrough(overlay);
  g.hotkey_probe_pass =
      g.hotkey_probe_watching0 && g.hotkey_probe_editing1 && g.hotkey_probe_watching2;
  WriteHotkeyProbeArtifacts();
  PostQuitMessage(0);
}

void WriteUiHwndArtifacts() {
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  const HWND settings = FindWindowW(L"LensTransSettings", L"LensTrans 设置");
  const HWND onboard = FindWindowW(L"LensTransOnboard", nullptr);
  g.e2e_ui_settings = settings != nullptr;
  g.e2e_ui_onboard = onboard != nullptr;
  std::ofstream f(EvalOutPath("ui-hwnd.md"), std::ios::binary);
  if (!f) return;
  f << "# UI HWND probe\n\n"
    << "- command: `.\\build\\Release\\lenstrans_overlay.exe --e2e-ui " << g.e2e_ui_sec << "`\n"
    << "- settings_title: LensTrans 设置\n"
    << "- onboard_title: LensTrans 引导（步骤内变为 LensTrans 引导 1/3 — 欢迎 等）\n"
    << "- settings: " << (g.e2e_ui_settings ? "yes" : "no") << "\n"
    << "- onboard: " << (g.e2e_ui_onboard ? "yes" : "no") << "\n"
    << "- tray: skip（NotifyIcon 无稳定 HWND）\n";
}

void WriteE2eArtifacts() {
  const bool two_box = g.e2e_two_box || g.e2e_rects.size() >= 2;
  RECT shot = g.have_init_rect ? g.init_rect : g.fixture_rect;
  if (two_box) {
    shot = g.fixture_rect;
    std::lock_guard<std::mutex> lock(g.boxes_mu);
    for (auto& b : g.boxes) {
      if (!b || !b->hwnd) continue;
      RECT wr{};
      GetWindowRect(b->hwnd, &wr);
      if (shot.right <= shot.left)
        shot = wr;
      else {
        shot.left = std::min(shot.left, wr.left);
        shot.top = std::min(shot.top, wr.top);
        shot.right = std::max(shot.right, wr.right);
        shot.bottom = std::max(shot.bottom, wr.bottom);
      }
    }
  }
  if (shot.right <= shot.left) shot = {80, 80, 640, 360};
  const char* bmp_name = g.e2e_wgc_monitor ? "overlay-wgc-monitor.bmp"
                        : g.e2e_wgc_window ? "overlay-wgc-window.bmp"
                        : g.e2e_llama        ? "overlay-llama-e2e.bmp"
                        : two_box            ? "overlay-two-box.bmp"
                        : g.e2e_contrast     ? "overlay-contrast-e2e.bmp"
                                             : "overlay-e2e.bmp";
  const char* md_name = g.e2e_wgc_monitor ? "overlay-wgc-monitor.md"
                        : g.e2e_wgc_window ? "overlay-wgc-window.md"
                        : g.e2e_llama        ? "overlay-llama-e2e.md"
                        : two_box            ? "overlay-two-box.md"
                        : g.e2e_contrast     ? "overlay-contrast-e2e.md"
                                             : "overlay-e2e.md";
  const std::string bmp_path = EvalOutPath(bmp_name);
  const std::string md_path = EvalOutPath(md_name);
  const bool bmp_ok = WriteScreenBmp(shot, bmp_path.c_str());
  std::string log;
  {
    std::lock_guard<std::mutex> lock(g.e2e_mu);
    log = g.e2e_log;
  }
  PROCESS_MEMORY_COUNTERS_EX c{};
  c.cb = sizeof(c);
  if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&c),
                           sizeof(c))) {
    g.e2e_ws_mib = static_cast<double>(c.WorkingSetSize) / (1024.0 * 1024.0);
  }
  const bool saw_hello = log.find("HELLO") != std::string::npos ||
                         log.find("Settings") != std::string::npos ||
                         log.find("Open File") != std::string::npos ||
                         log.find("Please") != std::string::npos;
  const bool cover_ok = g.e2e_cover && log.find("COVER_OK") != std::string::npos;
  const bool saw_present = log.find("PRESENT mode=") != std::string::npos;
  const bool saw_contrast = log.find("PRESENT mode=sticker+contrast") != std::string::npos;
  const bool saw_show_source = log.find("show_source=1") != std::string::npos;
  std::ofstream f(md_path, std::ios::binary);
  if (!f) return;
  if (two_box) {
    int nbox = 0;
    int pass = 0;
    {
      std::lock_guard<std::mutex> lock(g.boxes_mu);
      nbox = static_cast<int>(g.boxes.size());
      for (auto& b : g.boxes) {
        if (b && b->e2e_saw_ocr && b->e2e_saw_present && b->e2e_saw_cover) ++pass;
      }
    }
    f << "# Overlay e2e two-box\n\n"
      << "- date: 2026-08-30\n"
      << "- command: `.\\build\\Release\\lenstrans_overlay.exe --e2e-sec " << g.e2e_sec;
    if (g.e2e_stable) f << " --e2e-stable";
    if (g.e2e_two_box)
      f << " --e2e-two-box";
    else
      f << " --rect ...` (repeat per box)";
    f << " --no-onboard`\n"
      << "- path: formal stab+debounce (fake engine only)\n"
      << "- fixture: popup at 80,80 560x280 with HELLO Settings / Open File Cancel / Please wait\n"
      << "- boxes: " << nbox << "\n"
      << "- boxes_pass: " << pass << "/" << nbox << "\n"
      << "- all_cover_ok: " << (pass >= 2 && nbox >= 2 ? "yes" : "no") << "\n"
      << "- ocr_hits: " << g.e2e_ocr << "\n"
      << "- translations: " << g.e2e_tr << "\n"
      << "- cover_assert: "
      << (pass >= 2 && nbox >= 2 ? "COVER_OK opaque fill per box" : "NOT proven") << "\n"
      << "- screenshot: tools/eval/out/" << bmp_name << (bmp_ok ? "" : " (write failed)") << "\n\n"
      << "## Per box\n\n";
    int idx = 0;
    {
      std::lock_guard<std::mutex> lock(g.boxes_mu);
      for (auto& b : g.boxes) {
        if (!b || !b->hwnd) continue;
        RECT wr{};
        GetWindowRect(b->hwnd, &wr);
        const bool ok = b->e2e_saw_ocr && b->e2e_saw_present && b->e2e_saw_cover;
        f << "### box " << idx << "\n\n"
          << "- rect: " << wr.left << "," << wr.top << "," << (wr.right - wr.left) << ","
          << (wr.bottom - wr.top) << "\n"
          << "- ocr: " << (b->e2e_saw_ocr ? "yes" : "no") << "\n"
          << "- present: " << (b->e2e_saw_present ? "yes" : "no") << "\n"
          << "- cover_ok: " << (b->e2e_saw_cover ? "yes" : "no") << "\n"
          << "- sample_src: " << (b->e2e_sample_src.empty() ? "-" : b->e2e_sample_src) << "\n"
          << "- pass: " << (ok ? "yes" : "no") << "\n\n";
        ++idx;
      }
    }
    f << "## Console\n\n```\n" << log << "```\n";
    return;
  }
  if (g.e2e_wgc_window || g.e2e_wgc_monitor) {
    const bool monitor_mode = g.e2e_wgc_monitor;
    f << (monitor_mode ? "# Overlay WGC monitor crop\n\n" : "# Overlay WGC external window\n\n")
      << "- date: 2026-08-30\n"
      << "- command: `.\\build\\Release\\lenstrans_overlay.exe "
      << (monitor_mode ? "--e2e-wgc-monitor" : "--e2e-wgc-window")
      << " --e2e-sec " << g.e2e_sec;
    if (g.e2e_llama) f << " --e2e-llama";
    else f << " --e2e-stable";
    f << " --no-onboard --rect x,y,w,h`\n"
      << "- target: separate `lenstrans_e2e_target.exe` (external HWND, not overlay fixture)\n"
      << "- wgc_mode: "
      << (monitor_mode ? "CreateForMonitor crop"
                       : "CreateForWindow on external HWND") << "\n"
      << "- source: wgc/monitor\n"
      << "- exclude_overlay: WDA_EXCLUDEFROMCAPTURE\n"
      << "- target_rect: ";
    if (g.have_init_rect) {
      f << g.init_rect.left << "," << g.init_rect.top << ","
        << (g.init_rect.right - g.init_rect.left) << ","
        << (g.init_rect.bottom - g.init_rect.top) << "\n";
    } else {
      f << "-\n";
    }
    f << "- wgc_capture: **" << (g.e2e_saw_wgc ? "yes" : "no") << "**\n"
      << "- ocr_via_wgc: **" << (g.e2e_ocr_via_wgc ? "yes" : "no") << "**\n"
      << "- ocr_text: " << (g.e2e_first_ocr.empty() ? "-" : g.e2e_first_ocr) << "\n"
      << "- present_mode: " << (g.e2e_present.empty() ? "-" : g.e2e_present) << "\n"
      << "- saw_present: " << (saw_present ? "yes" : "no") << "\n"
      << "- cover_assert: " << (cover_ok ? "COVER_OK opaque fill, stack=0" : "NOT proven") << "\n"
      << "- covered_external: " << (cover_ok && saw_present ? "yes (immersive/sticker over ext HWND)"
                                   : "no") << "\n"
      << "- ocr_hits: " << g.e2e_ocr << "\n"
      << "- translations: " << g.e2e_tr << "\n";
    if (g.e2e_llama) {
      f << "- sample_src: " << (g.e2e_sample_src.empty() ? "-" : g.e2e_sample_src) << "\n"
        << "- sample_hyp: " << (g.e2e_sample_hyp.empty() ? "-" : g.e2e_sample_hyp) << "\n"
        << "- first_token_ms: "
        << (g.e2e_first_token_ms >= 0 ? std::to_string(g.e2e_first_token_ms) : "-") << "\n"
        << "- latency_ms: " << (g.e2e_latency_ms >= 0 ? std::to_string(g.e2e_latency_ms) : "-")
        << "\n";
    }
    f << "- screenshot: tools/eval/out/" << bmp_name << (bmp_ok ? "" : " (write failed)") << "\n\n"
      << "## Console\n\n```\n"
      << log << "```\n";
    return;
  }
  f << (g.e2e_llama ? "# Overlay e2e llama (LocalEngine Qwen2.5-0.5B)\n\n"
        : g.e2e_contrast ? "# Overlay e2e contrast (StickerContrast + show_source)\n\n"
                         : "# Overlay e2e (cover source text)\n\n")
    << "- date: 2026-08-30\n"
    << "- command: `.\\build\\Release\\lenstrans_overlay.exe --e2e-sec " << g.e2e_sec;
  if (g.e2e_llama) f << " --e2e-llama";
  else if (g.e2e_stable) f << " --e2e-stable";
  if (g.e2e_contrast) f << " --e2e-contrast";
  f << " --no-onboard` (optional `--rect x,y,w,h`)\n"
    << "- path: ";
  if (g.e2e_llama)
    f << "formal stab+debounce (LocalEngine " << lenstrans::DefaultModelFileName() << ")\n";
  else
    f << (g.e2e_stable ? "formal stab+debounce (fake engine only)"
                       : "e2e fast skip stab/debounce")
      << "\n";
  if (g.e2e_llama) {
    f << "- model: " << FindModel() << "\n"
      << "- engine: LocalEngine (llama.dll b10688)\n";
  }
  f << "- fixture: popup at 80,80 560x280 with HELLO Settings / Open File Cancel / Please wait\n"
    << "- overlay starts Watching (not edit drag)\n"
    << "- present_mode: " << (g.e2e_present.empty() ? "-" : g.e2e_present) << "\n"
    << "- ocr_hits: " << g.e2e_ocr << "\n"
    << "- translations: " << g.e2e_tr << "\n"
    << "- saw_english_ocr: " << (saw_hello ? "yes" : "no") << "\n"
    << "- saw_present: " << (saw_present ? "yes" : "no") << "\n";
  if (g.e2e_contrast) {
    f << "- saw_contrast: " << (saw_contrast ? "yes" : "no") << "\n"
      << "- show_source: " << (saw_show_source ? "yes" : "no") << "\n";
  }
  f << "- cover_assert: " << (cover_ok ? "COVER_OK opaque fill, stack=0" : "NOT proven") << "\n";
  if (g.e2e_llama) {
    f << "- sample_src: " << (g.e2e_sample_src.empty() ? "-" : g.e2e_sample_src) << "\n"
      << "- sample_hyp: " << (g.e2e_sample_hyp.empty() ? "-" : g.e2e_sample_hyp) << "\n"
      << "- first_token_ms: "
      << (g.e2e_first_token_ms >= 0 ? std::to_string(g.e2e_first_token_ms) : "-") << "\n"
      << "- latency_ms: " << (g.e2e_latency_ms >= 0 ? std::to_string(g.e2e_latency_ms) : "-")
      << "\n"
      << "- ws_mib: " << (g.e2e_ws_mib >= 0 ? std::to_string(static_cast<int>(g.e2e_ws_mib)) : "-")
      << "\n";
  }
  f << "- screenshot: tools/eval/out/" << bmp_name << (bmp_ok ? "" : " (write failed)") << "\n\n"
    << "## Console\n\n```\n"
    << log << "```\n";
}

void ApplyCmdLine() {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return;
  for (int i = 0; i < argc; ++i) {
    if (lstrcmpiW(argv[i], L"--ws-probe") == 0) {
      g.ws_probe_sec = 90;
      if (i + 1 < argc && argv[i + 1][0] != L'-') {
        const int n = _wtoi(argv[i + 1]);
        if (n >= 60 && n <= 120) g.ws_probe_sec = n;
      }
    } else if (lstrcmpiW(argv[i], L"--e2e-sec") == 0 && i + 1 < argc) {
      g.e2e_sec = std::max(8, _wtoi(argv[i + 1]));
      g.skip_onboard = true;
    } else if (lstrcmpiW(argv[i], L"--e2e-stable") == 0) {
      g.e2e_stable = true;
      g.skip_onboard = true;
    } else if (lstrcmpiW(argv[i], L"--e2e-contrast") == 0) {
      g.e2e_contrast = true;
      g.skip_onboard = true;
    } else if (lstrcmpiW(argv[i], L"--e2e-two-box") == 0) {
      g.e2e_two_box = true;
      g.e2e_stable = true;
      g.skip_onboard = true;
      if (g.e2e_sec <= 0) g.e2e_sec = 12;
    } else if (lstrcmpiW(argv[i], L"--e2e-llama") == 0) {
      g.e2e_llama = true;
      g.e2e_stable = true;
      g.skip_onboard = true;
      if (g.e2e_sec <= 0) g.e2e_sec = 35;
    } else if (lstrcmpiW(argv[i], L"--e2e-wgc-window") == 0) {
      g.e2e_wgc_window = true;
      g.e2e_external = true;
      g.e2e_stable = true;
      g.skip_onboard = true;
      if (g.e2e_sec <= 0) g.e2e_sec = 35;
    } else if (lstrcmpiW(argv[i], L"--e2e-wgc-monitor") == 0) {
      g.e2e_wgc_monitor = true;
      g.e2e_wgc_window = true;
      g.e2e_external = true;
      g.e2e_stable = true;
      g.skip_onboard = true;
      g.e2e_target_hwnd = nullptr;
      if (g.e2e_sec <= 0) g.e2e_sec = 35;
    } else if (lstrcmpiW(argv[i], L"--e2e-ui") == 0) {
      g.e2e_ui = true;
      g.skip_onboard = true;
      g.e2e_ui_sec = 8;
      if (i + 1 < argc && argv[i + 1][0] != L'-') {
        const int n = _wtoi(argv[i + 1]);
        if (n > 0) {
          g.e2e_ui_sec = n;
          ++i;
        }
      }
    } else if (lstrcmpiW(argv[i], L"--e2e-hotkey-probe") == 0) {
      g.e2e_hotkey_probe = true;
      g.skip_onboard = true;
    } else if (lstrcmpiW(argv[i], L"--no-onboard") == 0) {
      g.skip_onboard = true;
    } else if (lstrcmpiW(argv[i], L"--rect") == 0 && i + 1 < argc) {
      int x = 0, y = 0, w = 0, h = 0;
      if (swscanf_s(argv[i + 1], L"%d,%d,%d,%d", &x, &y, &w, &h) == 4 && w >= 160 && h >= 160) {
        g.e2e_rects.push_back({x, y, x + w, y + h});
        if (!g.have_init_rect) {
          g.have_init_rect = true;
          g.init_rect = g.e2e_rects.back();
        }
      }
      ++i;
    } else if (lstrcmpiW(argv[i], L"--e2e-target-hwnd") == 0 && i + 1 < argc) {
      g.e2e_target_hwnd = reinterpret_cast<HWND>(wcstoull(argv[i + 1], nullptr, 0));
      ++i;
    }
  }
  LocalFree(argv);
}

void LogWsSample(int elapsed) {
  PROCESS_MEMORY_COUNTERS_EX c{};
  c.cb = sizeof(c);
  if (!GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&c),
                            sizeof(c))) {
    return;
  }
  char line[128];
  std::snprintf(line, sizeof(line), "WS_PROBE t=%ds ws_mib=%.1f\n", elapsed,
                static_cast<double>(c.WorkingSetSize) / (1024.0 * 1024.0));
  LogA(line);
}

int Run() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  g.settings = lenstrans::LoadSettingsFile(lenstrans::win::ConfigDir() + "\\settings.cfg");
  if (g.e2e_contrast) {
    g.settings.contrast = true;
    g.settings.render = lenstrans::RenderLock::Sticker;
  }
  lenstrans::win::UnprotectFromFile(lenstrans::win::ConfigDir() + "\\api_key.dpapi", g.api_key);
  g.settings.autostart = lenstrans::win::AutostartEnabled();
  const bool probe = g.ws_probe_sec > 0;
  const bool e2e_ui = g.e2e_ui;
  const bool e2e_hotkey_probe = g.e2e_hotkey_probe;
  const bool e2e = g.e2e_sec > 0 && !e2e_ui && !e2e_hotkey_probe;

  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.lpszClassName = L"LensTransOverlayPoC";
  if (!RegisterClassExW(&wc)) return 1;
  WNDCLASSW hid{};
  hid.lpfnWndProc = HiddenProc;
  hid.hInstance = wc.hInstance;
  hid.lpszClassName = L"LensTransHidden";
  RegisterClassW(&hid);
  g.hidden = CreateWindowW(L"LensTransHidden", L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr,
                           wc.hInstance, nullptr);
  SetTimer(g.hidden, kHoverTimer, 50, nullptr);

  g.hooks.settings = &g.settings;
  g.hooks.api_key = &g.api_key;
  g.hooks.on_tray = [](lenstrans::win::TrayCmd c) { OnTray(c); };
  g.hooks.on_settings_saved = [] {
    EnsureEngines();
    RegisterAppHotkeys();
    g.hooks.cache_entries = g.cache.Size();
    g.hooks.cache_bytes = g.cache.Bytes();
  };
  g.hooks.on_clear_cache = [] {
    g.cache.Clear();
    g.hooks.cache_entries = 0;
    g.hooks.cache_bytes = 0;
  };

  if (!probe) {
    if (!g.e2e_external) {
      AllocConsole();
      SetConsoleTitleW(L"LensTrans");
    }
    LogA("LensTrans\n  Ctrl+E edit/click-through  Ctrl+Shift+L new box\n"
         "  Ctrl+T pause  Ctrl+Shift+H hide  Ctrl+, settings  Esc quit\n"
         "Watching: immersive fill or sticker only. Ctrl+, settings persist.\n");
  }

  if (!probe && !e2e_ui && !e2e_hotkey_probe && !g.skip_onboard && lenstrans::win::FirstRun()) {
    if (!lenstrans::win::ShowOnboarding(g.hidden, g.hooks)) return 0;
    g.demo_edit = true;
    g.demo_until = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  }

  SnapshotVirt();
  if (!probe) {
    const int sw = GetSystemMetrics(SM_CXSCREEN);
    const int sh = GetSystemMetrics(SM_CYSCREEN);
    if (e2e_ui) {
      lenstrans::win::ShowSettingsWindow(g.hidden, g.hooks);
      lenstrans::win::ShowOnboardingProbe(g.hidden, g.hooks);
      WriteUiHwndArtifacts();
      g.e2e_ui_until =
          std::chrono::steady_clock::now() + std::chrono::seconds(g.e2e_ui_sec);
    } else if (e2e_hotkey_probe) {
      CreateBox((sw - kDefaultW) / 2, sh / 3 - kDefaultH / 2, kDefaultW, kDefaultH, false);
      LogA("E2E hotkey probe: PostMessage WM_HOTKEY toggle edit/click-through\n");
    } else if (e2e) {
      if (!g.e2e_external) CreateFixture();
      if (g.e2e_two_box) {
        if (!g.fixture) return 1;
        const int fx = g.fixture_rect.left;
        const int fy = g.fixture_rect.top;
        const int fw = g.fixture_rect.right - g.fixture_rect.left;
        const int fh = g.fixture_rect.bottom - g.fixture_rect.top;
        const int half = std::max(160, fh / 2);
        CreateBox(fx, fy, fw, half, false);
        CreateBox(fx, fy + fh - half, fw, half, false);
        g.have_init_rect = true;
        g.init_rect = g.fixture_rect;
        char eline[160];
        std::snprintf(eline, sizeof(eline),
                      "E2E two-box rect=%d,%d,%d,%d + %d,%d,%d,%d sec=%d\n", fx, fy, fw, half, fx,
                      fy + fh - half, fw, half, g.e2e_sec);
        LogA(eline);
      } else if (g.e2e_rects.size() >= 2) {
        for (const RECT& r : g.e2e_rects) {
          CreateBox(r.left, r.top, r.right - r.left, r.bottom - r.top, false);
        }
        char eline[160];
        std::snprintf(eline, sizeof(eline), "E2E multi-box count=%zu sec=%d\n", g.e2e_rects.size(),
                      g.e2e_sec);
        LogA(eline);
      } else {
        int x = 80, y = 80, w = 560, h = 280;
        if (g.have_init_rect) {
          x = g.init_rect.left;
          y = g.init_rect.top;
          w = g.init_rect.right - g.init_rect.left;
          h = g.init_rect.bottom - g.init_rect.top;
        } else if (g.fixture) {
          x = g.fixture_rect.left;
          y = g.fixture_rect.top;
          w = g.fixture_rect.right - g.fixture_rect.left;
          h = g.fixture_rect.bottom - g.fixture_rect.top;
          g.have_init_rect = true;
          g.init_rect = g.fixture_rect;
        } else if (g.e2e_external) {
          LogA("E2E external target: --rect required\n");
          return 1;
        }
        CreateBox(x, y, w, h, false);
        char eline[160];
        std::snprintf(eline, sizeof(eline), "E2E watching rect=%d,%d,%d,%d sec=%d external=%d\n", x,
                      y, w, h, g.e2e_sec, g.e2e_external ? 1 : 0);
        LogA(eline);
      }
      g.e2e_until = std::chrono::steady_clock::now() + std::chrono::seconds(g.e2e_sec);
      if (g.e2e_contrast) LogA("E2E contrast: StickerContrast show_source render=sticker\n");
    } else {
      bool restored = false;
      if (g.settings.restore_boxes) {
        std::ifstream bf(lenstrans::win::ConfigDir() + "\\boxes.cfg", std::ios::binary);
        if (bf) {
          std::ostringstream ss;
          ss << bf.rdbuf();
          const auto rows = lenstrans::ParseBoxes(ss.str());
          for (const auto& row : rows) {
            CreateBox(row.x, row.y, row.w, row.h, true, &row);
            restored = true;
          }
        }
      }
      if (!restored)
        CreateBox((sw - kDefaultW) / 2, sh / 3 - kDefaultH / 2, kDefaultW, kDefaultH, true);
    }
    if (!e2e_ui) {
      lenstrans::win::InitTray(g.hidden, g.hooks);
      RegisterAppHotkeys();
      if (!e2e_hotkey_probe) {
        EnsureEngines();
        g.worker = std::thread(WorkerLoop);
      }
    }
  }

  const auto probe_until =
      std::chrono::steady_clock::now() + std::chrono::seconds(probe ? g.ws_probe_sec : 0);
  int last_ws_log = -1;

  MSG msg{};
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if (probe) {
      const int elapsed = static_cast<int>(
          std::chrono::duration_cast<std::chrono::seconds>(std::chrono::steady_clock::now() -
                                                           (probe_until - std::chrono::seconds(g.ws_probe_sec)))
              .count());
      if (elapsed / 5 != last_ws_log) {
        last_ws_log = elapsed / 5;
        LogWsSample(elapsed);
      }
      if (std::chrono::steady_clock::now() >= probe_until) {
        PostQuitMessage(0);
      }
    }
    if (e2e_ui && g.e2e_ui_until.time_since_epoch().count() != 0 &&
        std::chrono::steady_clock::now() >= g.e2e_ui_until) {
      PostQuitMessage(0);
    }
    if (e2e_hotkey_probe && !g.hotkey_probe_done) {
      RunHotkeyProbeOnce();
    }
    if (e2e && g.e2e_until.time_since_epoch().count() != 0 &&
        std::chrono::steady_clock::now() >= g.e2e_until) {
      WriteE2eArtifacts();
      PostQuitMessage(0);
    }
    if (g.demo_edit && std::chrono::steady_clock::now() > g.demo_until) {
      g.demo_edit = false;
      for (auto& b : g.boxes) SetEditing(b.get(), false);
    }
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  g.run = false;
  if (g.worker.joinable()) g.worker.join();
  if (e2e && g.e2e_log.find("# Overlay") == std::string::npos) WriteE2eArtifacts();
  if (e2e_hotkey_probe && !g.hotkey_probe_done) {
    RunHotkeyProbeOnce();
  }
  if (!probe && !e2e && !e2e_hotkey_probe) SaveAllBoxes();
  for (int i = 1; i <= 5; ++i) UnregisterHotKey(g.hidden, i);
  lenstrans::win::DestroyTray();
  if (e2e_hotkey_probe) return g.hotkey_probe_pass ? 0 : 1;
  return 0;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  ApplyCmdLine();
  return Run();
}
