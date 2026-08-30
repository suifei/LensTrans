#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include <windows.h>

#include <algorithm>
#include <cstdio>

namespace {

constexpr UINT kSwitchTextMsg = WM_APP;
constexpr int kTimerQuit = 1;
constexpr int kTimerAutoSwitch = 2;

const wchar_t* kTextPhase0 = L"HELLO Settings";
const wchar_t* kTextPhase1 = L"Please wait";

int g_text_phase = 0;
int g_auto_switch_ms = 0;

void SwitchToPhase1(HWND hwnd) {
  if (g_text_phase >= 1) return;
  g_text_phase = 1;
  InvalidateRect(hwnd, nullptr, TRUE);
  std::printf("E2E_TARGET switched text=Please wait\n");
  std::fflush(stdout);
}

LRESULT CALLBACK TargetProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
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
    DrawTextW(hdc, g_text_phase >= 1 ? kTextPhase1 : kTextPhase0, -1, &line,
              DT_LEFT | DT_TOP | DT_SINGLELINE);
    SelectObject(hdc, oldf);
    DeleteObject(font);
    EndPaint(hwnd, &ps);
    return 0;
  }
  if (msg == WM_LBUTTONDOWN) {
    std::printf("CLICKED\n");
    std::fflush(stdout);
    return 0;
  }
  if (msg == WM_KEYDOWN && wparam == VK_F2) {
    SwitchToPhase1(hwnd);
    return 0;
  }
  if (msg == kSwitchTextMsg) {
    SwitchToPhase1(hwnd);
    return 0;
  }
  if (msg == WM_TIMER && wparam == kTimerQuit) {
    PostQuitMessage(0);
    return 0;
  }
  if (msg == WM_TIMER && wparam == kTimerAutoSwitch) {
    SwitchToPhase1(hwnd);
    KillTimer(hwnd, kTimerAutoSwitch);
    return 0;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

void PrintClientScreenRect(HWND hwnd) {
  RECT cr{};
  GetClientRect(hwnd, &cr);
  POINT tl{0, 0};
  ClientToScreen(hwnd, &tl);
  const int w = cr.right - cr.left;
  const int h = cr.bottom - cr.top;
  std::printf("E2E_TARGET rect=%d,%d,%d,%d hwnd=%p\n", tl.x, tl.y, w, h,
              static_cast<void*>(hwnd));
  std::fflush(stdout);
}

}  // namespace

int ParseSwitchAtSec(int argc, wchar_t** argv) {
  for (int i = 1; i + 1 < argc; ++i) {
    if (lstrcmpiW(argv[i], L"--switch-at") == 0) {
      return std::max(0, _wtoi(argv[i + 1]));
    }
  }
  return 0;
}

int main(int argc, wchar_t** argv) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  g_auto_switch_ms = ParseSwitchAtSec(argc, argv) * 1000;

  WNDCLASSW wc{};
  wc.lpfnWndProc = TargetProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH));
  wc.lpszClassName = L"LensTransE2eTarget";
  RegisterClassW(&wc);

  const int x = 120, y = 120, w = 560, h = 280;
  HWND hwnd = CreateWindowExW(0, L"LensTransE2eTarget", L"LensTrans WGC Target",
                              WS_POPUP | WS_VISIBLE, x, y, w, h, nullptr, nullptr, wc.hInstance,
                              nullptr);
  if (!hwnd) return 1;
  ShowWindow(hwnd, SW_SHOW);
  UpdateWindow(hwnd);
  PrintClientScreenRect(hwnd);
  SetTimer(hwnd, kTimerQuit, 40000, nullptr);
  if (g_auto_switch_ms > 0) SetTimer(hwnd, kTimerAutoSwitch, g_auto_switch_ms, nullptr);

  MSG msg{};
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  return 0;
}
