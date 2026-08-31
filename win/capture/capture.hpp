#pragma once

#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN

#include <windows.h>

#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

namespace lenstrans::win {

// Hide overlay from WGC/monitor capture (Windows 10 2004+). Returns false on failure.
bool ExcludeOverlayFromCapture(HWND overlay);

struct BgraFrame {
  int w = 0;
  int h = 0;
  std::vector<std::uint8_t> bgra;
  std::string source;  // "wgc" | "printwindow" | "bitblt"
};

class RegionCapture {
 public:
  RegionCapture();
  ~RegionCapture();
  RegionCapture(const RegionCapture&) = delete;
  RegionCapture& operator=(const RegionCapture&) = delete;

  // screen_phys: overlay client in physical pixels (Per-Monitor V2).
  // wgc_target: optional foreign HWND for CreateForWindow (e2e external window).
  bool Start(HWND overlay, RECT screen_phys, HWND wgc_target = nullptr);
  void UpdateRect(RECT screen_phys);
  bool Grab(BgraFrame& out);
  // WGC only — no BitBlt/PrintWindow. For permission probes.
  bool GrabWgcOnly(BgraFrame& out);
  void Stop();
  std::string LastError() const;

 private:
  bool GrabWgc(BgraFrame& out);
  bool GrabPrintWindow(BgraFrame& out);
  bool GrabBitBlt(BgraFrame& out);
  void StopLocked();

  struct Impl;
  Impl* impl_ = nullptr;
  HWND overlay_ = nullptr;
  RECT rect_{};
  std::string err_;
  mutable std::mutex mu_;
  bool wgc_failed_ = false;
};

}  // namespace lenstrans::win
