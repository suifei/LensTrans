#include "lenstrans/settings.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdio>

using namespace lenstrans;

static int g_fail = 0;

#define CHECK(cond)                                                               \
  do {                                                                            \
    if (!(cond)) {                                                                \
      std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);        \
      ++g_fail;                                                                   \
    }                                                                             \
  } while (0)

static LRESULT CALLBACK HiddenWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  return DefWindowProcW(hwnd, msg, wp, lp);
}

static HWND CreateHiddenWindow() {
  const wchar_t kCls[] = L"LensTransHotkeyTest";
  WNDCLASSW wc{};
  wc.lpfnWndProc = HiddenWndProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kCls;
  RegisterClassW(&wc);
  return CreateWindowExW(0, kCls, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
}

static void TestRegisterDefaultHotkeys(HWND hwnd) {
  const Settings s{};
  struct Hotkey {
    int id;
    int mod;
    int vk;
    const char* label;
  };
  const Hotkey keys[] = {
      {901, s.mod_new | MOD_NOREPEAT, s.vk_new, "Ctrl+Shift+L"},
      {902, s.mod_edit | MOD_NOREPEAT, s.vk_edit, "Ctrl+E"},
      {903, s.mod_pause | MOD_NOREPEAT, s.vk_pause, "Ctrl+T"},
      {904, s.mod_hide | MOD_NOREPEAT, s.vk_hide, "Ctrl+Shift+H"},
  };
  for (const auto& hk : keys) {
    const BOOL ok = RegisterHotKey(hwnd, hk.id, static_cast<UINT>(hk.mod), static_cast<UINT>(hk.vk));
    CHECK(ok != 0);
    if (ok) CHECK(UnregisterHotKey(hwnd, hk.id) != 0);
  }
}

int main() {
  const HWND hwnd = CreateHiddenWindow();
  CHECK(hwnd != nullptr);
  TestRegisterDefaultHotkeys(hwnd);
  if (hwnd) DestroyWindow(hwnd);
  if (g_fail) {
    std::fprintf(stderr, "%d hotkey checks failed\n", g_fail);
    return 1;
  }
  std::printf("test_hotkey: all checks passed\n");
  return 0;
}
