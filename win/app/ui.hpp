#pragma once

#ifndef UNICODE
#define UNICODE
#endif
#include <windows.h>

#include "lenstrans/settings.hpp"

#include <functional>
#include <string>

namespace lenstrans::win {

enum class TrayCmd {
  ToggleBoxes = 1,
  NewBox,
  Pause,
  EngineLocal,
  EngineCloud,
  EngineAuto,
  LangZh,
  LangEn,
  LangJa,
  LangKo,
  ModeTrans,
  ModeContrast,
  Autostart,
  Settings,
  Update,
  ClearCache,
  Quit,
};

struct AppHooks {
  std::function<void(TrayCmd)> on_tray;
  std::function<void()> on_settings_saved;
  std::function<void()> on_clear_cache;
  Settings* settings = nullptr;
  std::string* api_key = nullptr;
  std::size_t cache_entries = 0;
  std::size_t cache_bytes = 0;
  bool running = true;
  bool paused = false;
  bool boxes_visible = true;
};

bool InitTray(HWND hwnd, AppHooks& hooks);
void UpdateTrayTip(const wchar_t* tip);
void DestroyTray();
void ShowTrayMenu(HWND hwnd, AppHooks& hooks);
void ShowSettingsWindow(HWND owner, AppHooks& hooks);
bool ShowOnboarding(HWND owner, AppHooks& hooks);
HWND ShowOnboardingProbe(HWND owner, AppHooks& hooks);
bool TrayIconActive();
bool FirstRun();
HWND SettingsWindowHandle();
HWND OnboardingWindowHandle();

}  // namespace lenstrans::win
