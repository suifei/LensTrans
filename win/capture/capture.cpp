#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "win/capture/capture.hpp"

#include <unknwn.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.UI.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "windowsapp.lib")

#ifndef WDA_EXCLUDEFROMCAPTURE
#define WDA_EXCLUDEFROMCAPTURE 0x00000011
#endif
#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 0x00000002
#endif

using winrt::Windows::Graphics::Capture::Direct3D11CaptureFramePool;
using winrt::Windows::Graphics::Capture::GraphicsCaptureItem;
using winrt::Windows::Graphics::Capture::GraphicsCaptureSession;
using winrt::Windows::Graphics::DirectX::DirectXPixelFormat;
using winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DDevice;
using winrt::Windows::Graphics::SizeInt32;

namespace lenstrans::win {
namespace {

IDirect3DDevice WrapDevice(ID3D11Device* d3d) {
  winrt::com_ptr<IDXGIDevice> dxgi;
  winrt::check_hresult(d3d->QueryInterface(__uuidof(IDXGIDevice), dxgi.put_void()));
  winrt::com_ptr<IInspectable> inspectable;
  winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
  return inspectable.as<IDirect3DDevice>();
}

winrt::com_ptr<ID3D11Texture2D> TextureFromSurface(
    winrt::Windows::Graphics::DirectX::Direct3D11::IDirect3DSurface const& surface) {
  auto access = surface.as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
  winrt::com_ptr<ID3D11Texture2D> tex;
  winrt::check_hresult(access->GetInterface(IID_PPV_ARGS(tex.put())));
  return tex;
}

}  // namespace

bool ExcludeOverlayFromCapture(HWND overlay) {
  if (!overlay) return false;
  return SetWindowDisplayAffinity(overlay, WDA_EXCLUDEFROMCAPTURE) != FALSE;
}

struct RegionCapture::Impl {
  winrt::com_ptr<ID3D11Device> d3d;
  winrt::com_ptr<ID3D11DeviceContext> ctx;
  IDirect3DDevice device{nullptr};
  GraphicsCaptureItem item{nullptr};
  Direct3D11CaptureFramePool pool{nullptr};
  GraphicsCaptureSession session{nullptr};
  HMONITOR monitor = nullptr;
  RECT monitor_rect{};
  HWND wgc_window = nullptr;
  bool capture_window = false;
  int pool_w = 0;
  int pool_h = 0;
  bool apartment = false;
  std::vector<std::uint8_t> wgc_cache;
  int wgc_cache_w = 0;
  int wgc_cache_h = 0;
};

bool FrameHasInk(const BgraFrame& fr) {
  if (fr.bgra.empty()) return false;
  for (std::size_t i = 0; i + 3 < fr.bgra.size(); i += 64) {
    if (fr.bgra[i] < 240 || fr.bgra[i + 1] < 240 || fr.bgra[i + 2] < 240) return true;
  }
  return false;
}

bool FrameIsCaptureHole(const BgraFrame& fr) {
  if (fr.bgra.empty()) return true;
  int dark = 0;
  int samples = 0;
  for (std::size_t i = 0; i + 3 < fr.bgra.size(); i += 64) {
    ++samples;
    if (fr.bgra[i] < 16 && fr.bgra[i + 1] < 16 && fr.bgra[i + 2] < 16) ++dark;
  }
  return samples > 0 && dark * 10 >= samples * 9;
}

HWND TopWindowAtPointSkip(POINT pt, HWND skip) {
  struct Ctx {
    POINT pt;
    HWND skip;
    HWND hit = nullptr;
  } ctx{pt, skip, nullptr};
  EnumWindows(
      [](HWND hwnd, LPARAM lp) -> BOOL {
        auto* c = reinterpret_cast<Ctx*>(lp);
        if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return TRUE;
        if (c->skip && (hwnd == c->skip || IsChild(c->skip, hwnd))) return TRUE;
        wchar_t cls[64]{};
        GetClassNameW(hwnd, cls, 64);
        if (lstrcmpW(cls, L"ConsoleWindowClass") == 0 || lstrcmpW(cls, L"LensTransHidden") == 0 ||
            lstrcmpW(cls, L"LensTransOverlayPoC") == 0 || lstrcmpW(cls, L"LensTransSettings") == 0 ||
            lstrcmpW(cls, L"LensTransOnboard") == 0) {
          return TRUE;
        }
        RECT wr{};
        GetWindowRect(hwnd, &wr);
        if (!PtInRect(&wr, c->pt)) return TRUE;
        if (lstrcmpW(cls, L"LensTransE2eTarget") == 0) {
          c->hit = hwnd;
          return FALSE;
        }
        if (!c->hit) c->hit = hwnd;
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&ctx));
  return ctx.hit;
}

MIDL_INTERFACE("BBBC098B-2186-588D-8580-2701A74C0525")
IDisplayGraphicsCaptureSessionInterop : IInspectable {
 public:
  virtual HRESULT STDMETHODCALLTYPE SetWindowExclusionList(void* excludedWindows) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetWindowExclusionList(void** excludedWindows) = 0;
};

bool ApplyMonitorOverlayExclusion(GraphicsCaptureSession session, HWND overlay) {
  if (!overlay || !session) return false;
  winrt::com_ptr<IDisplayGraphicsCaptureSessionInterop> disp;
  if (FAILED(winrt::get_unknown(session)->QueryInterface(
          __uuidof(IDisplayGraphicsCaptureSessionInterop), disp.put_void()))) {
    return false;
  }
  winrt::Windows::UI::WindowId wid{};
  using GetWindowIdFromWindowFn = HRESULT(WINAPI*)(HWND, ABI::Windows::UI::WindowId*);
  if (auto* fn = reinterpret_cast<GetWindowIdFromWindowFn>(
          GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetWindowIdFromWindow"));
      fn && SUCCEEDED(fn(overlay, reinterpret_cast<ABI::Windows::UI::WindowId*>(&wid)))) {
  } else {
    wid.Value = static_cast<uint64_t>(reinterpret_cast<uintptr_t>(overlay));
  }
  auto list = winrt::single_threaded_vector<winrt::Windows::UI::WindowId>();
  list.Append(wid);
  const auto view = list.GetView();
  if (FAILED(disp->SetWindowExclusionList(winrt::get_abi(view)))) return false;
  return true;
}

RegionCapture::RegionCapture() = default;

RegionCapture::~RegionCapture() { Stop(); }

bool RegionCapture::Start(HWND overlay, RECT screen_phys, HWND wgc_target) {
  std::lock_guard<std::mutex> lock(mu_);
  StopLocked();
  err_.clear();
  wgc_failed_ = false;
  overlay_ = overlay;
  rect_ = screen_phys;
  impl_ = new Impl();
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    impl_->apartment = true;
  } catch (...) {
    // already initialized
  }
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  D3D_FEATURE_LEVEL fl;
  HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, nullptr, 0,
                                 D3D11_SDK_VERSION, impl_->d3d.put(), &fl, impl_->ctx.put());
  if (FAILED(hr)) {
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags, nullptr, 0,
                           D3D11_SDK_VERSION, impl_->d3d.put(), &fl, impl_->ctx.put());
  }
  if (FAILED(hr)) {
    err_ = "D3D11CreateDevice failed";
    delete impl_;
    impl_ = nullptr;
    return false;
  }
  try {
    impl_->device = WrapDevice(impl_->d3d.get());
    auto factory = winrt::get_activation_factory<GraphicsCaptureItem>();
    auto interop = factory.as<IGraphicsCaptureItemInterop>();
    HWND effective_target = wgc_target;
    if (!effective_target || !IsWindow(effective_target)) {
      POINT c{(screen_phys.left + screen_phys.right) / 2,
              (screen_phys.top + screen_phys.bottom) / 2};
      effective_target = TopWindowAtPointSkip(c, overlay);
      if (effective_target == GetDesktopWindow()) effective_target = nullptr;
    }
    if (effective_target && IsWindow(effective_target)) {
      impl_->capture_window = true;
      impl_->wgc_window = effective_target;
      GetWindowRect(effective_target, &impl_->monitor_rect);
    } else {
      impl_->monitor = MonitorFromWindow(overlay_, MONITOR_DEFAULTTONEAREST);
      if (!impl_->monitor) {
        POINT pt{screen_phys.left + 1, screen_phys.top + 1};
        impl_->monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
      }
      MONITORINFO mi{sizeof(mi)};
      if (!impl_->monitor || !GetMonitorInfoW(impl_->monitor, &mi)) {
        err_ = "monitor lookup failed";
        delete impl_;
        impl_ = nullptr;
        return false;
      }
      impl_->monitor_rect = mi.rcMonitor;
    }
    if (impl_->capture_window) {
      winrt::check_hresult(interop->CreateForWindow(
          impl_->wgc_window, winrt::guid_of<GraphicsCaptureItem>(), winrt::put_abi(impl_->item)));
    } else {
      winrt::check_hresult(interop->CreateForMonitor(
          impl_->monitor, winrt::guid_of<GraphicsCaptureItem>(), winrt::put_abi(impl_->item)));
    }
    const auto sz = impl_->item.Size();
    impl_->pool_w = sz.Width;
    impl_->pool_h = sz.Height;
    impl_->pool = Direct3D11CaptureFramePool::CreateFreeThreaded(
        impl_->device, DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, sz);
    impl_->session = impl_->pool.CreateCaptureSession(impl_->item);
    impl_->session.IsCursorCaptureEnabled(false);
    // Keep the affinity exclusion in place for both capture modes. The monitor
    // exclusion-list API is a second line of defense on newer Windows builds.
    if (overlay_) ExcludeOverlayFromCapture(overlay_);
    impl_->session.StartCapture();
    if (!impl_->capture_window && overlay_) {
      ApplyMonitorOverlayExclusion(impl_->session, overlay_);
    }
  } catch (const winrt::hresult_error& e) {
    char hr[16];
    std::snprintf(hr, sizeof(hr), "0x%08X", static_cast<unsigned>(e.code()));
    err_ = std::string("WGC start failed: ") + winrt::to_string(e.message()) + " hr=" + hr;
    delete impl_;
    impl_ = nullptr;
    return false;
  }
  return true;
}

void RegionCapture::UpdateRect(RECT screen_phys) {
  std::lock_guard<std::mutex> lock(mu_);
  rect_ = screen_phys;
}

void RegionCapture::StopLocked() {
  if (!impl_) return;
  try {
    if (impl_->session) impl_->session.Close();
    if (impl_->pool) impl_->pool.Close();
  } catch (...) {
  }
  delete impl_;
  impl_ = nullptr;
}

void RegionCapture::Stop() {
  std::lock_guard<std::mutex> lock(mu_);
  StopLocked();
}

bool RegionCapture::GrabWgc(BgraFrame& out) {
  if (wgc_failed_ || !impl_ || !impl_->pool) return false;
  winrt::Windows::Graphics::Capture::Direct3D11CaptureFrame frame{nullptr};
  try {
    frame = impl_->pool.TryGetNextFrame();
  } catch (...) {
    frame = nullptr;
  }
  if (!frame) {
    if (!impl_->wgc_cache.empty()) {
      out.w = impl_->wgc_cache_w;
      out.h = impl_->wgc_cache_h;
      out.bgra = impl_->wgc_cache;
      out.source = "wgc";
      if (!FrameIsCaptureHole(out) || FrameHasInk(out)) return true;
    }
    return false;
  }
  try {
    auto tex = TextureFromSurface(frame.Surface());
    D3D11_TEXTURE2D_DESC desc{};
    tex->GetDesc(&desc);
    D3D11_TEXTURE2D_DESC staging = desc;
    staging.Usage = D3D11_USAGE_STAGING;
    staging.BindFlags = 0;
    staging.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    staging.MiscFlags = 0;
    winrt::com_ptr<ID3D11Texture2D> cpu;
    if (FAILED(impl_->d3d->CreateTexture2D(&staging, nullptr, cpu.put()))) return false;
    impl_->ctx->CopyResource(cpu.get(), tex.get());
    D3D11_MAPPED_SUBRESOURCE map{};
    if (FAILED(impl_->ctx->Map(cpu.get(), 0, D3D11_MAP_READ, 0, &map))) return false;
    const int mx = impl_->monitor_rect.left;
    const int my = impl_->monitor_rect.top;
    const int mon_w = impl_->monitor_rect.right - impl_->monitor_rect.left;
    const int mon_h = impl_->monitor_rect.bottom - impl_->monitor_rect.top;
    double sx = 1.0;
    double sy = 1.0;
    if (mon_w > 0 && mon_h > 0 &&
        (static_cast<int>(desc.Width) != mon_w || static_cast<int>(desc.Height) != mon_h)) {
      sx = static_cast<double>(desc.Width) / mon_w;
      sy = static_cast<double>(desc.Height) / mon_h;
    }
    int x0 = static_cast<int>((rect_.left - mx) * sx);
    int y0 = static_cast<int>((rect_.top - my) * sy);
    int x1 = static_cast<int>((rect_.right - mx) * sx);
    int y1 = static_cast<int>((rect_.bottom - my) * sy);
    x0 = std::max(0, std::min(static_cast<int>(desc.Width), x0));
    y0 = std::max(0, std::min(static_cast<int>(desc.Height), y0));
    x1 = std::max(x0, std::min(static_cast<int>(desc.Width), x1));
    y1 = std::max(y0, std::min(static_cast<int>(desc.Height), y1));
    const int w = x1 - x0;
    const int h = y1 - y0;
    if (w <= 0 || h <= 0) {
      impl_->ctx->Unmap(cpu.get(), 0);
      return false;
    }
    out.w = w;
    out.h = h;
    out.bgra.resize(static_cast<std::size_t>(w) * h * 4);
    out.source = "wgc";
    auto* src = static_cast<const std::uint8_t*>(map.pData);
    for (int y = 0; y < h; ++y) {
      std::memcpy(out.bgra.data() + static_cast<std::size_t>(y) * w * 4,
                  src + static_cast<std::size_t>(y0 + y) * map.RowPitch + static_cast<std::size_t>(x0) * 4,
                  static_cast<std::size_t>(w) * 4);
    }
    impl_->ctx->Unmap(cpu.get(), 0);
    impl_->wgc_cache = out.bgra;
    impl_->wgc_cache_w = out.w;
    impl_->wgc_cache_h = out.h;
    return true;
  } catch (...) {
    return false;
  }
}

bool RegionCapture::GrabBitBlt(BgraFrame& out) {
  const int w = rect_.right - rect_.left;
  const int h = rect_.bottom - rect_.top;
  if (w <= 0 || h <= 0) return false;
  HDC screen = GetDC(nullptr);
  if (!screen) return false;
  HDC mem = CreateCompatibleDC(screen);
  if (!mem) {
    ReleaseDC(nullptr, screen);
    return false;
  }
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!dib || !bits) {
    if (dib) DeleteObject(dib);
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
    return false;
  }
  HGDIOBJ old = SelectObject(mem, dib);
  const BOOL ok = BitBlt(mem, 0, 0, w, h, screen, rect_.left, rect_.top, SRCCOPY);
  if (ok && bits) {
    out.w = w;
    out.h = h;
    out.bgra.resize(static_cast<std::size_t>(w) * h * 4);
    std::memcpy(out.bgra.data(), bits, out.bgra.size());
    out.source = "bitblt";
  }
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  return ok == TRUE && !out.bgra.empty();
}

bool RegionCapture::GrabPrintWindow(BgraFrame& out) {
  POINT c{(rect_.left + rect_.right) / 2, (rect_.top + rect_.bottom) / 2};
  HWND target = TopWindowAtPointSkip(c, overlay_);
  if (!target || target == GetDesktopWindow()) return false;
  const int w = rect_.right - rect_.left;
  const int h = rect_.bottom - rect_.top;
  if (w <= 0 || h <= 0) return false;
  HDC screen = GetDC(nullptr);
  if (!screen) return false;
  HDC mem = CreateCompatibleDC(screen);
  if (!mem) {
    ReleaseDC(nullptr, screen);
    return false;
  }
  RECT wr{};
  if (!GetWindowRect(target, &wr)) {
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
    return false;
  }
  const int ww = std::max(1, wr.right - wr.left);
  const int wh = std::max(1, wr.bottom - wr.top);
  BITMAPINFO bi{};
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bi.bmiHeader.biWidth = ww;
  bi.bmiHeader.biHeight = -wh;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  bi.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(screen, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!dib || !bits) {
    if (dib) DeleteObject(dib);
    DeleteDC(mem);
    ReleaseDC(nullptr, screen);
    return false;
  }
  HGDIOBJ old = SelectObject(mem, dib);
  const int ox = rect_.left - wr.left;
  const int oy = rect_.top - wr.top;
  BOOL ok = PrintWindow(target, mem, PW_RENDERFULLCONTENT);
  if (!ok) ok = PrintWindow(target, mem, 0);
  if (ok && bits) {
    out.w = w;
    out.h = h;
    out.bgra.assign(static_cast<std::size_t>(w) * h * 4, 0);
    const auto* src = static_cast<const std::uint8_t*>(bits);
    for (int y = 0; y < h; ++y) {
      const int sy = oy + y;
      if (sy < 0 || sy >= wh) continue;
      const int src_x = std::max(0, ox);
      const int dst_x = std::max(0, -ox);
      const int copy_w = std::min(w - dst_x, ww - src_x);
      if (copy_w <= 0) continue;
      std::memcpy(out.bgra.data() + static_cast<std::size_t>(y) * w * 4 + dst_x * 4,
                  src + static_cast<std::size_t>(sy) * ww * 4 + src_x * 4,
                  static_cast<std::size_t>(copy_w) * 4);
    }
    out.source = "printwindow";
  }
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  return ok == TRUE && !out.bgra.empty();
}

bool RegionCapture::GrabWgcOnly(BgraFrame& out) {
  std::lock_guard<std::mutex> lock(mu_);
  out = {};
  if (GrabWgc(out)) return true;
  if (!impl_)
    err_ = err_.empty() ? "WGC not started" : err_;
  else
    err_ = "WGC frame empty";
  return false;
}

bool RegionCapture::Grab(BgraFrame& out) {
  std::lock_guard<std::mutex> lock(mu_);
  out = {};
  // WGC can need a few compositor ticks after StartCapture. Keep this short so a
  // broken WGC session reaches the explicit GDI fallback instead of stalling the UI.
  constexpr int kMaxAttempts = 4;
  for (int attempt = 0; attempt < kMaxAttempts && !wgc_failed_; ++attempt) {
    if (!GrabWgc(out)) {
      out = {};
      if (impl_ && attempt + 1 < kMaxAttempts) Sleep(50);
      continue;
    }
    if (FrameIsCaptureHole(out) && !FrameHasInk(out)) {
      out = {};
      if (impl_ && attempt + 1 < kMaxAttempts) Sleep(50);
      continue;
    }
    return true;
  }
  if (impl_) wgc_failed_ = true;
  const std::string wgc_error = impl_ ? "WGC frame unavailable" : "WGC not started";
  if (GrabPrintWindow(out)) {
    err_ = wgc_error + "; fallback=printwindow";
    return true;
  }
  if (GrabBitBlt(out)) {
    err_ = wgc_error + "; fallback=bitblt";
    return true;
  }
  err_ = wgc_error + "; fallback=failed";
  return false;
}

std::string RegionCapture::LastError() const {
  std::lock_guard<std::mutex> lock(mu_);
  return err_;
}

}  // namespace lenstrans::win
