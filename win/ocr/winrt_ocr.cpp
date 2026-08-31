#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "win/ocr/winrt_ocr.hpp"

#include <unknwn.h>
#include <MemoryBuffer.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <map>
#include <thread>

#pragma comment(lib, "windowsapp.lib")

using ::Windows::Foundation::IMemoryBufferByteAccess;
using winrt::Windows::Globalization::Language;
using winrt::Windows::Graphics::Imaging::BitmapBufferAccessMode;
using winrt::Windows::Graphics::Imaging::BitmapPixelFormat;
using winrt::Windows::Graphics::Imaging::SoftwareBitmap;
using winrt::Windows::Media::Ocr::OcrEngine;
using winrt::Windows::Media::Ocr::OcrResult;

namespace lenstrans::win {
namespace {

std::string WideToUtf8(std::wstring_view w) {
  if (w.empty()) return {};
  const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0,
                                    nullptr, nullptr);
  std::string s(static_cast<std::size_t>(n), 0);
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), s.data(), n, nullptr,
                      nullptr);
  return s;
}

SoftwareBitmap ToSoftwareBitmap(const BgraFrame& frame, const RECT& crop) {
  const int x0 = std::max(0, static_cast<int>(crop.left));
  const int y0 = std::max(0, static_cast<int>(crop.top));
  const int x1 = std::min(frame.w, static_cast<int>(crop.right));
  const int y1 = std::min(frame.h, static_cast<int>(crop.bottom));
  const int w = std::max(1, x1 - x0);
  const int h = std::max(1, y1 - y0);
  auto bmp = SoftwareBitmap(BitmapPixelFormat::Bgra8, w, h,
                            winrt::Windows::Graphics::Imaging::BitmapAlphaMode::Ignore);
  {
    auto buf = bmp.LockBuffer(BitmapBufferAccessMode::Write);
    auto ref = buf.CreateReference();
    // BitmapBuffer::CreateReference is IMemoryBufferReference, not IBuffer.
    // QI IBufferByteAccess → E_NOINTERFACE ("不支持此接口").
    uint8_t* dst = nullptr;
    UINT32 cap = 0;
    auto access = ref.as<IMemoryBufferByteAccess>();
    winrt::check_hresult(access->GetBuffer(&dst, &cap));
    const auto desc = buf.GetPlaneDescription(0);
    for (int y = 0; y < h; ++y) {
      const std::uint8_t* src = frame.bgra.data() +
                                static_cast<std::size_t>(y0 + y) * frame.w * 4 +
                                static_cast<std::size_t>(x0) * 4;
      std::uint8_t* row = dst + static_cast<std::size_t>(y) * desc.Stride;
      std::memcpy(row, src, static_cast<std::size_t>(w) * 4);
      for (int x = 0; x < w; ++x) row[x * 4 + 3] = 255;
    }
    ref.Close();
  }
  return bmp;
}

RECT UnionRois(const BgraFrame& frame, const std::vector<OcrRoi>& rois) {
  if (rois.empty()) return {0, 0, frame.w, frame.h};
  RECT u{frame.w, frame.h, 0, 0};
  for (const auto& r : rois) {
    u.left = std::min(static_cast<int>(u.left), r.x);
    u.top = std::min(static_cast<int>(u.top), r.y);
    u.right = std::max(static_cast<int>(u.right), r.x + r.w);
    u.bottom = std::max(static_cast<int>(u.bottom), r.y + r.h);
  }
  u.left = std::max(0, static_cast<int>(u.left));
  u.top = std::max(0, static_cast<int>(u.top));
  u.right = std::min(frame.w, static_cast<int>(u.right));
  u.bottom = std::min(frame.h, static_cast<int>(u.bottom));
  if (u.right <= u.left || u.bottom <= u.top) return {0, 0, frame.w, frame.h};
  return u;
}

}  // namespace

void SampleColorAndVariance(const BgraFrame& frame, OcrBlock& block) {
  if (frame.bgra.empty() || frame.w <= 0) return;
  const int x0 = std::max(0, static_cast<int>(block.bbox.x));
  const int y0 = std::max(0, static_cast<int>(block.bbox.y));
  const int x1 = std::min(frame.w, static_cast<int>(block.bbox.x + block.bbox.w));
  const int y1 = std::min(frame.h, static_cast<int>(block.bbox.y + block.bbox.h));
  if (x1 <= x0 || y1 <= y0) return;

  std::map<std::uint32_t, int> hist;
  int dark_r = 0, dark_g = 0, dark_b = 0, dark_n = 0;
  for (int y = y0; y < y1; ++y) {
    const std::uint8_t* row = frame.bgra.data() + static_cast<std::size_t>(y) * frame.w * 4;
    for (int x = x0; x < x1; ++x) {
      const int b = row[x * 4], g = row[x * 4 + 1], r = row[x * 4 + 2];
      const int lum = (r + g + b) / 3;
      const std::uint32_t q = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      hist[q]++;
      if (lum < 128) {
        dark_r += r;
        dark_g += g;
        dark_b += b;
        ++dark_n;
      }
    }
  }
  if (dark_n > 0) {
    block.color.r = static_cast<std::uint8_t>(dark_r / dark_n);
    block.color.g = static_cast<std::uint8_t>(dark_g / dark_n);
    block.color.b = static_cast<std::uint8_t>(dark_b / dark_n);
  }

  const int ring = 6;
  double sr = 0, sg = 0, sb = 0, n = 0;
  auto acc = [&](int x, int y) {
    if (x < 0 || y < 0 || x >= frame.w || y >= frame.h) return;
    const std::uint8_t* p = frame.bgra.data() + static_cast<std::size_t>(y) * frame.w * 4 + x * 4;
    sr += p[2];
    sg += p[1];
    sb += p[0];
    n += 1;
  };
  for (int y = y0 - ring; y < y1 + ring; ++y) {
    for (int x = x0 - ring; x < x1 + ring; ++x) {
      const bool inside = x >= x0 && x < x1 && y >= y0 && y < y1;
      if (!inside) acc(x, y);
    }
  }
  if (n < 1) return;
  const double mr = sr / n, mg = sg / n, mb = sb / n;
  block.background.r = static_cast<std::uint8_t>(std::clamp(mr, 0.0, 255.0));
  block.background.g = static_cast<std::uint8_t>(std::clamp(mg, 0.0, 255.0));
  block.background.b = static_cast<std::uint8_t>(std::clamp(mb, 0.0, 255.0));
  double vr = 0, vg = 0, vb = 0;
  auto var = [&](int x, int y) {
    if (x < 0 || y < 0 || x >= frame.w || y >= frame.h) return;
    const std::uint8_t* p = frame.bgra.data() + static_cast<std::size_t>(y) * frame.w * 4 + x * 4;
    vr += (p[2] - mr) * (p[2] - mr);
    vg += (p[1] - mg) * (p[1] - mg);
    vb += (p[0] - mb) * (p[0] - mb);
  };
  for (int y = y0 - ring; y < y1 + ring; ++y) {
    for (int x = x0 - ring; x < x1 + ring; ++x) {
      const bool inside = x >= x0 && x < x1 && y >= y0 && y < y1;
      if (!inside) var(x, y);
    }
  }
  block.bg_variance = static_cast<float>(std::sqrt((vr + vg + vb) / (3.0 * n)));
}

std::vector<OcrBlock> RecognizeOcr(const BgraFrame& frame, const std::vector<OcrRoi>& rois,
                                   std::string& err) {
  err.clear();
  std::vector<OcrBlock> out;
  if (frame.bgra.empty() || frame.w < 8 || frame.h < 8) {
    err = "OCR_EMPTY";
    return out;
  }
  try {
    std::exception_ptr sta_ep;
    std::thread sta([&] {
      try {
        winrt::init_apartment(winrt::apartment_type::single_threaded);
        OcrEngine engine = OcrEngine::TryCreateFromUserProfileLanguages();
        if (!engine && OcrEngine::IsLanguageSupported(Language{L"en-US"})) {
          engine = OcrEngine::TryCreateFromLanguage(Language{L"en-US"});
        }
        if (!engine) {
          err = "OCR engine unavailable (no user-profile/en-US language pack)";
          winrt::uninit_apartment();
          return;
        }
        const RECT crop = UnionRois(frame, rois);
        auto bmp = ToSoftwareBitmap(frame, crop);
        OcrResult result = engine.RecognizeAsync(bmp).get();
        for (auto const& line : result.Lines()) {
          OcrBlock block;
          block.text = WideToUtf8(std::wstring_view(line.Text()));
          if (block.text.empty()) continue;
          float minx = 1e9f, miny = 1e9f, maxx = -1e9f, maxy = -1e9f;
          for (auto const& word : line.Words()) {
            const auto r = word.BoundingRect();
            minx = std::min(minx, static_cast<float>(r.X));
            miny = std::min(miny, static_cast<float>(r.Y));
            maxx = std::max(maxx, static_cast<float>(r.X + r.Width));
            maxy = std::max(maxy, static_cast<float>(r.Y + r.Height));
          }
          if (maxx < minx) continue;
          block.bbox.x = minx + static_cast<float>(crop.left);
          block.bbox.y = miny + static_cast<float>(crop.top);
          block.bbox.w = maxx - minx;
          block.bbox.h = maxy - miny;
          block.line_height = block.bbox.h;
          SampleColorAndVariance(frame, block);
          if (!rois.empty()) {
            bool hit = false;
            for (const auto& r : rois) {
              const float rx1 = static_cast<float>(r.x + r.w);
              const float ry1 = static_cast<float>(r.y + r.h);
              if (block.bbox.x < rx1 && block.bbox.x + block.bbox.w > r.x &&
                  block.bbox.y < ry1 && block.bbox.y + block.bbox.h > r.y) {
                hit = true;
                break;
              }
            }
            if (!hit) continue;
          }
          out.push_back(std::move(block));
        }
        if (out.empty()) err = "OCR_EMPTY";
        winrt::uninit_apartment();
      } catch (...) {
        sta_ep = std::current_exception();
      }
    });
    sta.join();
    if (sta_ep) std::rethrow_exception(sta_ep);
  } catch (const winrt::hresult_error& e) {
    char hr[20];
    std::snprintf(hr, sizeof(hr), "0x%08X", static_cast<unsigned>(e.code()));
    err = std::string(hr) + " " + winrt::to_string(e.message());
  } catch (const std::exception& e) {
    err = e.what();
  }
  return out;
}

}  // namespace lenstrans::win
