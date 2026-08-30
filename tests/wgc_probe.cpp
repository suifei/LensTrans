#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "win/capture/capture.hpp"
#include "win/ocr/winrt_ocr.hpp"
#include "lenstrans/paths.hpp"

#include <windows.h>

#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

static lenstrans::win::BgraFrame MakeHelloFrame() {
  const int w = 360, h = 140;
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
  RECT rc{0, 0, w, h};
  FillRect(mem, &rc, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
  SetBkMode(mem, TRANSPARENT);
  SetTextColor(mem, RGB(0, 0, 0));
  HFONT font = CreateFontW(36, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, 0, 0,
                           L"Segoe UI");
  HGDIOBJ oldf = SelectObject(mem, font);
  DrawTextW(mem, L"HELLO Settings", -1, &rc, DT_LEFT | DT_TOP | DT_SINGLELINE);
  SelectObject(mem, oldf);
  DeleteObject(font);
  lenstrans::win::BgraFrame fr;
  fr.w = w;
  fr.h = h;
  fr.source = "gdi";
  fr.bgra.resize(static_cast<std::size_t>(w) * h * 4);
  if (bits) memcpy(fr.bgra.data(), bits, fr.bgra.size());
  for (size_t i = 3; i < fr.bgra.size(); i += 4) fr.bgra[i] = 255;
  SelectObject(mem, old);
  DeleteObject(dib);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  return fr;
}

int main() {
  const std::string outp = lenstrans::JoinPath(lenstrans::EvalOutDir(), "wgc-probe.md");
  lenstrans::EnsureDir(lenstrans::EvalOutDir());
  std::string status = "unknown";
  std::string detail;
  int w = 0, h = 0;
  std::string source;
  std::string ocr_note = "not run";
  const auto t0 = std::chrono::steady_clock::now();

  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  POINT pt{GetSystemMetrics(SM_XVIRTUALSCREEN) + 80, GetSystemMetrics(SM_YVIRTUALSCREEN) + 80};
  HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{sizeof(mi)};
  GetMonitorInfoW(mon, &mi);
  RECT cap{mi.rcMonitor.left + 64, mi.rcMonitor.top + 64, mi.rcMonitor.left + 224,
           mi.rcMonitor.top + 184};

  HWND hwnd = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"STATIC", L"LensTransWgcProbe",
                              WS_POPUP, 0, 0, 8, 8, nullptr, nullptr, GetModuleHandleW(nullptr),
                              nullptr);
  lenstrans::win::RegionCapture capr;
  const bool started = capr.Start(hwnd, cap);
  if (!started) {
    detail = capr.LastError();
    const bool denied = detail.find("denied") != std::string::npos ||
                        detail.find("Denied") != std::string::npos ||
                        detail.find("0x80070005") != std::string::npos ||
                        detail.find("access") != std::string::npos;
    status = denied ? "denied" : "failed";
    std::printf("WGC_PROBE start_fail %s\n", detail.c_str());
  } else {
    lenstrans::win::BgraFrame fr;
    bool got = false;
    for (int i = 0; i < 20; ++i) {
      if (capr.GrabWgcOnly(fr)) {
        got = true;
        break;
      }
      Sleep(150);
      const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                          std::chrono::steady_clock::now() - t0)
                          .count();
      if (ms > 4000) break;
    }
    if (got && fr.source == "wgc" && !fr.bgra.empty()) {
      status = "authorized";
      w = fr.w;
      h = fr.h;
      source = fr.source;
      detail = "GrabWgcOnly ok";
      std::printf("DIFF wgc %dx%d\n", w, h);
      std::string oerr;
      auto blocks = lenstrans::win::RecognizeOcr(fr, {}, oerr);
      if (!blocks.empty()) {
        ocr_note = std::string("wgc OCR lines=") + std::to_string(blocks.size()) + " first=\"" +
                   blocks[0].text + "\"";
        std::printf("OCR %s\n", ocr_note.c_str());
      } else {
        ocr_note = std::string("wgc OCR ") + (oerr.empty() ? "OCR_EMPTY" : oerr);
        std::printf("OCR %s\n", ocr_note.c_str());
      }
    } else {
      detail = capr.LastError();
      status = "no_frame";
      std::printf("WGC_PROBE no_frame %s\n", detail.c_str());
    }
  }
  capr.Stop();
  if (hwnd) DestroyWindow(hwnd);

  std::string mem_ocr = "not run";
  bool mem_ok = false;
  {
    auto syn = MakeHelloFrame();
    std::string oerr;
    auto blocks = lenstrans::win::RecognizeOcr(syn, {}, oerr);
    if (!blocks.empty()) {
      mem_ocr = std::string("lines=") + std::to_string(blocks.size()) + " first=\"" +
                blocks[0].text + "\"";
      for (const auto& b : blocks) {
        if (b.text.find("HELLO") != std::string::npos || b.text.find("Hello") != std::string::npos ||
            b.text.find("Settings") != std::string::npos)
          mem_ok = true;
      }
    } else {
      mem_ocr = oerr.empty() ? "OCR_EMPTY" : oerr;
    }
    std::printf("MEM_OCR %s mem_ok=%d\n", mem_ocr.c_str(), mem_ok ? 1 : 0);
  }

  const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::steady_clock::now() - t0)
                      .count();
  std::ofstream f(outp.c_str(), std::ios::binary);
  if (f) {
    f << "# WGC probe + OCR fix\n\n"
      << "- date: 2026-08-30\n"
      << "- reproduce: `.\\build\\Release\\lenstrans_wgc_probe.exe` or "
      << "`powershell -File tools\\eval\\wgc-probe.ps1`\n"
      << "- root cause: `SoftwareBitmap.LockBuffer` → `IMemoryBufferReference`. Old code QI "
      << "`IBufferByteAccess` → E_NOINTERFACE / 不支持此接口. Fix: `IMemoryBufferByteAccess::GetBuffer`.\n"
      << "- wgc status: **" << status << "**\n"
      << "- elapsed_ms: " << ms << "\n"
      << "- start_ok: " << (started ? "yes" : "no") << "\n"
      << "- frame: " << w << "x" << h << " source=" << (source.empty() ? "-" : source) << "\n"
      << "- wgc detail: " << detail << "\n"
      << "- wgc ocr (desktop crop, may have no English): " << ocr_note << "\n"
      << "- mem ocr (GDI HELLO Settings): " << mem_ocr << " mem_ok=" << (mem_ok ? "yes" : "no")
      << "\n";
  }
  std::printf("WGC_PROBE status=%s mem_ok=%d ms=%lld\n", status.c_str(), mem_ok ? 1 : 0,
              static_cast<long long>(ms));
  if (!mem_ok) return 1;
  return status == "authorized" ? 0 : 2;
}
