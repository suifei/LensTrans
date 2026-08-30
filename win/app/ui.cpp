#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "win/app/ui.hpp"
#include "win/app/secrets.hpp"
#include "win/capture/capture.hpp"
#include "lenstrans/present.hpp"

#include <commctrl.h>
#include <shellapi.h>

#include <algorithm>
#include <string>

using lenstrans::EnginePref;
using lenstrans::FindHotkeyConflict;
using lenstrans::FormatHotkey;
using lenstrans::RenderLock;
using lenstrans::SaveSettingsFile;
using lenstrans::Settings;

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")

namespace lenstrans::win {
namespace {

struct OnbUi {
  HWND body = nullptr;
  HWND local = nullptr;
  HWND next = nullptr;
  HWND back = nullptr;
  int step = 0;
  bool done = false;
  bool ok = false;
  AppHooks* hooks = nullptr;
};

NOTIFYICONDATAW g_nid{};
AppHooks* g_hooks = nullptr;
HWND g_settings = nullptr;
HWND g_onboard = nullptr;
OnbUi* g_onboard_ui = nullptr;

std::wstring Utf8(const std::string& s) {
  if (s.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(static_cast<std::size_t>(n), 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

std::string Narrow(HWND edit) {
  wchar_t buf[1024]{};
  GetWindowTextW(edit, buf, 1024);
  const int n = WideCharToMultiByte(CP_UTF8, 0, buf, -1, nullptr, 0, nullptr, nullptr);
  std::string s(static_cast<std::size_t>(n ? n - 1 : 0), 0);
  if (n > 1) WideCharToMultiByte(CP_UTF8, 0, buf, -1, s.data(), n, nullptr, nullptr);
  return s;
}

void CheckMenu(HMENU m, UINT id, bool on) {
  CheckMenuItem(m, id, MF_BYCOMMAND | (on ? MF_CHECKED : MF_UNCHECKED));
}

HWND MakeEdit(HWND p, int x, int y, int w, int hh, int id, const std::wstring& text, bool pw) {
  DWORD ex = WS_EX_CLIENTEDGE;
  DWORD st = WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | (pw ? ES_PASSWORD : 0);
  HWND ctrl = CreateWindowExW(ex, L"EDIT", text.c_str(), st, x, y, w, hh, p,
                              reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr),
                              nullptr);
  SendMessageW(ctrl, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  return ctrl;
}

HWND MakeBtn(HWND p, int x, int y, int w, int hh, int id, const wchar_t* t) {
  HWND ctrl = CreateWindowW(L"BUTTON", t, WS_CHILD | WS_VISIBLE, x, y, w, hh, p,
                            reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr),
                            nullptr);
  SendMessageW(ctrl, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  return ctrl;
}

HWND MakeChk(HWND p, int x, int y, int w, int hh, int id, const wchar_t* t, bool on) {
  HWND ctrl = CreateWindowW(L"BUTTON", t, WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, x, y, w, hh, p,
                            reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr),
                            nullptr);
  SendMessageW(ctrl, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  SendMessageW(ctrl, BM_SETCHECK, on ? BST_CHECKED : BST_UNCHECKED, 0);
  return ctrl;
}

HWND MakeRadio(HWND p, int x, int y, int w, int hh, int id, const wchar_t* t, bool on, bool group) {
  DWORD st = WS_CHILD | WS_VISIBLE | BS_AUTORADIOBUTTON | (group ? WS_GROUP : 0);
  HWND ctrl = CreateWindowW(L"BUTTON", t, st, x, y, w, hh, p,
                            reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), GetModuleHandleW(nullptr),
                            nullptr);
  SendMessageW(ctrl, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  SendMessageW(ctrl, BM_SETCHECK, on ? BST_CHECKED : BST_UNCHECKED, 0);
  return ctrl;
}

HWND MakeLbl(HWND p, int x, int y, int w, int hh, const wchar_t* t) {
  HWND ctrl = CreateWindowW(L"STATIC", t, WS_CHILD | WS_VISIBLE, x, y, w, hh, p, nullptr,
                            GetModuleHandleW(nullptr), nullptr);
  SendMessageW(ctrl, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  return ctrl;
}

constexpr int kTab = 100;
constexpr int kOk = 101;
constexpr int kCancel = 102;
constexpr int kPrivacy = 201;
constexpr int kAutostart = 202;
constexpr int kRestore = 203;
constexpr int kEngAuto = 301;
constexpr int kEngLocal = 302;
constexpr int kEngCloud = 303;
constexpr int kBase = 304;
constexpr int kKey = 305;
constexpr int kModel = 306;
constexpr int kTest = 307;
constexpr int kQuality = 308;
constexpr int kRendAuto = 401;
constexpr int kRendSticker = 402;
constexpr int kRendImm = 403;
constexpr int kContrast = 404;
constexpr int kAlpha = 405;
constexpr int kScale = 406;
constexpr int kAbout = 501;
constexpr int kClearCache = 502;
constexpr int kHkBtn0 = 601;
constexpr UINT kHkTimer = 1;
constexpr int kOnbNext = 701;
constexpr int kOnbBack = 702;
constexpr int kOnbLocal = 703;
constexpr int kOnbCancel = 704;

struct SettingsUi {
  HWND tabs = nullptr;
  HWND pages[5]{};
  AppHooks* hooks = nullptr;
  HWND hk_lbl[5]{};
  int hk_mod[5]{};
  int hk_vk[5]{};
  int capturing = -1;
};

static const wchar_t* kHkNames[] = {L"新建翻译框", L"编辑模式", L"暂停/继续", L"全显/全隐", L"设置"};

std::wstring HkText(int mod, int vk) { return Utf8(FormatHotkey(mod, vk)); }

void RefreshHkLabels(SettingsUi* ui) {
  const int c = FindHotkeyConflict(ui->hk_mod, ui->hk_vk, 5);
  for (int i = 0; i < 5; ++i) {
    if (!ui->hk_lbl[i]) continue;
    std::wstring t = std::wstring(kHkNames[i]) + L"  " + HkText(ui->hk_mod[i], ui->hk_vk[i]);
    if (ui->capturing == i) t += L"  （按下新组合…）";
    else if (c == i || (c >= 0 && ui->hk_mod[i] == ui->hk_mod[c] && ui->hk_vk[i] == ui->hk_vk[c] && i != c))
      t += L"  冲突";
    SetWindowTextW(ui->hk_lbl[i], t.c_str());
  }
}

void PollHotkeyCapture(HWND hwnd, SettingsUi* ui) {
  if (!ui || ui->capturing < 0 || ui->capturing > 4) return;
  for (int vk = 8; vk < 256; ++vk) {
    if (vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_SHIFT ||
        vk == VK_LSHIFT || vk == VK_RSHIFT || vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU ||
        vk == VK_LWIN || vk == VK_RWIN || vk == VK_CAPITAL || vk == VK_NUMLOCK || vk == VK_SCROLL)
      continue;
    if ((GetAsyncKeyState(vk) & 0x8000) == 0) continue;
    if (vk == VK_ESCAPE) {
      ui->capturing = -1;
      KillTimer(hwnd, kHkTimer);
      RefreshHkLabels(ui);
      return;
    }
    int mod = 0;
    if (GetAsyncKeyState(VK_MENU) & 0x8000) mod |= 1;
    if (GetAsyncKeyState(VK_CONTROL) & 0x8000) mod |= 2;
    if (GetAsyncKeyState(VK_SHIFT) & 0x8000) mod |= 4;
    if ((GetAsyncKeyState(VK_LWIN) | GetAsyncKeyState(VK_RWIN)) & 0x8000) mod |= 8;
    if (mod == 0) mod = 2;
    ui->hk_mod[ui->capturing] = mod;
    ui->hk_vk[ui->capturing] = vk;
    ui->capturing = -1;
    KillTimer(hwnd, kHkTimer);
    RefreshHkLabels(ui);
    return;
  }
}

void ShowPage(SettingsUi* ui, int i) {
  for (int p = 0; p < 5; ++p) {
    if (ui->pages[p]) ShowWindow(ui->pages[p], p == i ? SW_SHOW : SW_HIDE);
  }
}

void Collect(HWND dlg, SettingsUi* ui) {
  if (!ui->hooks || !ui->hooks->settings) return;
  Settings& s = *ui->hooks->settings;
  HWND p0 = ui->pages[0];
  HWND p1 = ui->pages[1];
  HWND p2 = ui->pages[2];
  const bool want_auto = SendDlgItemMessageW(p0, kAutostart, BM_GETCHECK, 0, 0) == BST_CHECKED;
  SetAutostart(want_auto);
  s.autostart = AutostartEnabled();
  s.restore_boxes = SendDlgItemMessageW(p0, kRestore, BM_GETCHECK, 0, 0) == BST_CHECKED;
  s.privacy = SendDlgItemMessageW(p1, kPrivacy, BM_GETCHECK, 0, 0) == BST_CHECKED;
  if (SendDlgItemMessageW(p1, kEngLocal, BM_GETCHECK, 0, 0) == BST_CHECKED) s.engine = EnginePref::Local;
  else if (SendDlgItemMessageW(p1, kEngCloud, BM_GETCHECK, 0, 0) == BST_CHECKED)
    s.engine = EnginePref::Cloud;
  else
    s.engine = EnginePref::Auto;
  s.cloud_base_url = Narrow(GetDlgItem(p1, kBase));
  s.cloud_model = Narrow(GetDlgItem(p1, kModel));
  if (ui->hooks->api_key) *ui->hooks->api_key = Narrow(GetDlgItem(p1, kKey));
  s.quality = SendDlgItemMessageW(p1, kQuality, BM_GETCHECK, 0, 0) == BST_CHECKED;
  if (SendDlgItemMessageW(p2, kRendSticker, BM_GETCHECK, 0, 0) == BST_CHECKED)
    s.render = RenderLock::Sticker;
  else if (SendDlgItemMessageW(p2, kRendImm, BM_GETCHECK, 0, 0) == BST_CHECKED)
    s.render = RenderLock::Immersive;
  else
    s.render = RenderLock::Auto;
  s.contrast = SendDlgItemMessageW(p2, kContrast, BM_GETCHECK, 0, 0) == BST_CHECKED;
  wchar_t buf[32]{};
  GetWindowTextW(GetDlgItem(p2, kAlpha), buf, 32);
  s.sticker_alpha = std::max(60, std::min(100, _wtoi(buf)));
  GetWindowTextW(GetDlgItem(p2, kScale), buf, 32);
  s.font_scale = std::max(80, std::min(150, _wtoi(buf)));
  s.mod_new = ui->hk_mod[0];
  s.vk_new = ui->hk_vk[0];
  s.mod_edit = ui->hk_mod[1];
  s.vk_edit = ui->hk_vk[1];
  s.mod_pause = ui->hk_mod[2];
  s.vk_pause = ui->hk_vk[2];
  s.mod_hide = ui->hk_mod[3];
  s.vk_hide = ui->hk_vk[3];
  s.mod_settings = ui->hk_mod[4];
  s.vk_settings = ui->hk_vk[4];
  ProtectToFile(ConfigDir() + "\\api_key.dpapi", ui->hooks->api_key ? *ui->hooks->api_key : "");
  SaveSettingsFile(ConfigDir() + "\\settings.cfg", s);
  if (ui->hooks->on_settings_saved) ui->hooks->on_settings_saved();
  (void)dlg;
}

LRESULT CALLBACK SettingsProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  auto* ui = reinterpret_cast<SettingsUi*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (msg) {
    case WM_NOTIFY: {
      const auto* hdr = reinterpret_cast<NMHDR*>(lp);
      if (hdr->idFrom == kTab && hdr->code == TCN_SELCHANGE && ui) {
        ShowPage(ui, TabCtrl_GetCurSel(ui->tabs));
      }
      return 0;
    }
    case WM_TIMER:
      if (wp == kHkTimer && ui) PollHotkeyCapture(hwnd, ui);
      return 0;
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
      if (ui && ui->capturing >= 0 && ui->capturing < 5) {
        PollHotkeyCapture(hwnd, ui);
        return 0;
      }
      return DefWindowProcW(hwnd, msg, wp, lp);
    case WM_COMMAND:
      if (LOWORD(wp) == kOk && ui) {
        Collect(hwnd, ui);
        DestroyWindow(hwnd);
      } else if (LOWORD(wp) == kCancel) {
        DestroyWindow(hwnd);
      } else if (LOWORD(wp) >= kHkBtn0 && LOWORD(wp) < kHkBtn0 + 5 && ui) {
        ui->capturing = LOWORD(wp) - kHkBtn0;
        RefreshHkLabels(ui);
        SetTimer(hwnd, kHkTimer, 50, nullptr);
        SetFocus(hwnd);
      } else if (LOWORD(wp) == kClearCache && ui && ui->hooks) {
        if (ui->hooks->on_clear_cache) ui->hooks->on_clear_cache();
        wchar_t note[128];
        swprintf_s(note, L"缓存已清理。当前 %zu 条。", ui->hooks->cache_entries);
        MessageBoxW(hwnd, note, L"LensTrans", MB_OK);
      } else if (LOWORD(wp) == kTest && ui) {
        const std::string r = ProbeCloud(Narrow(GetDlgItem(ui->pages[1], kBase)),
                                         Narrow(GetDlgItem(ui->pages[1], kModel)));
        MessageBoxW(hwnd, Utf8(r).c_str(), L"测试连接", MB_OK);
      }
      return 0;
    case WM_DESTROY:
      KillTimer(hwnd, kHkTimer);
      delete ui;
      g_settings = nullptr;
      return 0;
    default:
      return DefWindowProcW(hwnd, msg, wp, lp);
  }
}

}  // namespace

bool InitTray(HWND hwnd, AppHooks& hooks) {
  g_hooks = &hooks;
  g_nid = {};
  g_nid.cbSize = sizeof(g_nid);
  g_nid.hWnd = hwnd;
  g_nid.uID = 1;
  g_nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  g_nid.uCallbackMessage = WM_APP + 1;
  g_nid.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  wcscpy_s(g_nid.szTip, L"LensTrans");
  return Shell_NotifyIconW(NIM_ADD, &g_nid) != FALSE;
}

bool TrayIconActive() { return g_nid.hWnd != nullptr && g_nid.uID != 0; }

void UpdateTrayTip(const wchar_t* tip) {
  wcsncpy_s(g_nid.szTip, tip, _TRUNCATE);
  g_nid.uFlags = NIF_TIP;
  Shell_NotifyIconW(NIM_MODIFY, &g_nid);
}

void DestroyTray() { Shell_NotifyIconW(NIM_DELETE, &g_nid); }

void ShowTrayMenu(HWND hwnd, AppHooks& hooks) {
  POINT pt{};
  GetCursorPos(&pt);
  HMENU m = CreatePopupMenu();
  AppendMenuW(m, MF_STRING, static_cast<UINT>(TrayCmd::ToggleBoxes), L"显示/隐藏全部翻译框\tCtrl+Shift+H");
  AppendMenuW(m, MF_STRING, static_cast<UINT>(TrayCmd::NewBox), L"新建翻译框\tCtrl+Shift+L");
  AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(m, MF_STRING, static_cast<UINT>(TrayCmd::Pause),
              hooks.paused ? L"继续翻译\tCtrl+T" : L"暂停翻译\tCtrl+T");
  HMENU eng = CreatePopupMenu();
  AppendMenuW(eng, MF_STRING, static_cast<UINT>(TrayCmd::EngineLocal), L"本地（快）");
  AppendMenuW(eng, MF_STRING, static_cast<UINT>(TrayCmd::EngineCloud), L"云端（强）");
  AppendMenuW(eng, MF_STRING, static_cast<UINT>(TrayCmd::EngineAuto), L"自动");
  if (hooks.settings) {
    CheckMenu(eng, static_cast<UINT>(TrayCmd::EngineLocal), hooks.settings->engine == EnginePref::Local);
    CheckMenu(eng, static_cast<UINT>(TrayCmd::EngineCloud), hooks.settings->engine == EnginePref::Cloud);
    CheckMenu(eng, static_cast<UINT>(TrayCmd::EngineAuto), hooks.settings->engine == EnginePref::Auto);
  }
  AppendMenuW(m, MF_POPUP, reinterpret_cast<UINT_PTR>(eng), L"翻译引擎");
  HMENU lang = CreatePopupMenu();
  AppendMenuW(lang, MF_STRING, static_cast<UINT>(TrayCmd::LangZh), L"简体中文");
  AppendMenuW(lang, MF_STRING, static_cast<UINT>(TrayCmd::LangEn), L"English");
  AppendMenuW(lang, MF_STRING, static_cast<UINT>(TrayCmd::LangJa), L"日本語");
  AppendMenuW(lang, MF_STRING, static_cast<UINT>(TrayCmd::LangKo), L"한국어");
  if (hooks.settings) {
    CheckMenu(lang, static_cast<UINT>(TrayCmd::LangZh), hooks.settings->tgt_lang == "zh");
    CheckMenu(lang, static_cast<UINT>(TrayCmd::LangEn), hooks.settings->tgt_lang == "en");
    CheckMenu(lang, static_cast<UINT>(TrayCmd::LangJa), hooks.settings->tgt_lang == "ja");
    CheckMenu(lang, static_cast<UINT>(TrayCmd::LangKo), hooks.settings->tgt_lang == "ko");
  }
  AppendMenuW(m, MF_POPUP, reinterpret_cast<UINT_PTR>(lang), L"目标语言");
  HMENU mode = CreatePopupMenu();
  AppendMenuW(mode, MF_STRING, static_cast<UINT>(TrayCmd::ModeTrans), L"仅译文");
  AppendMenuW(mode, MF_STRING, static_cast<UINT>(TrayCmd::ModeContrast), L"双语对照");
  if (hooks.settings) {
    CheckMenu(mode, static_cast<UINT>(TrayCmd::ModeTrans), !hooks.settings->contrast);
    CheckMenu(mode, static_cast<UINT>(TrayCmd::ModeContrast), hooks.settings->contrast);
  }
  AppendMenuW(m, MF_POPUP, reinterpret_cast<UINT_PTR>(mode), L"显示模式");
  AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(m, MF_STRING, static_cast<UINT>(TrayCmd::Autostart), L"开机自启");
  const bool auto_on = AutostartEnabled();
  if (hooks.settings) hooks.settings->autostart = auto_on;
  CheckMenu(m, static_cast<UINT>(TrayCmd::Autostart), auto_on);
  AppendMenuW(m, MF_STRING, static_cast<UINT>(TrayCmd::Settings), L"设置…\tCtrl+,");
  AppendMenuW(m, MF_STRING, static_cast<UINT>(TrayCmd::Update), L"检查更新");
  AppendMenuW(m, MF_STRING, static_cast<UINT>(TrayCmd::Quit), L"退出");
  SetForegroundWindow(hwnd);
  const int cmd = TrackPopupMenu(m, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, nullptr);
  DestroyMenu(m);
  if (cmd && hooks.on_tray) hooks.on_tray(static_cast<TrayCmd>(cmd));
}

void ShowSettingsWindow(HWND owner, AppHooks& hooks) {
  if (g_settings) {
    SetForegroundWindow(g_settings);
    return;
  }
  INITCOMMONCONTROLSEX icc{sizeof(icc), ICC_TAB_CLASSES};
  InitCommonControlsEx(&icc);
  WNDCLASSW wc{};
  wc.lpfnWndProc = SettingsProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"LensTransSettings";
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&wc);
  HWND hwnd = CreateWindowExW(WS_EX_DLGMODALFRAME, wc.lpszClassName, L"LensTrans 设置",
                              WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT,
                              480, 560, owner, nullptr, wc.hInstance, nullptr);
  ExcludeOverlayFromCapture(hwnd);
  auto* ui = new SettingsUi{};
  ui->hooks = &hooks;
  SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(ui));
  ui->tabs = CreateWindowW(WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 8, 8, 448,
                           470, hwnd, reinterpret_cast<HMENU>(kTab), wc.hInstance, nullptr);
  SendMessageW(ui->tabs, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  TCITEMW it{};
  it.mask = TCIF_TEXT;
  const wchar_t* names[] = {L"通用", L"翻译", L"呈现", L"热键", L"关于"};
  for (int i = 0; i < 5; ++i) {
    it.pszText = const_cast<wchar_t*>(names[i]);
    TabCtrl_InsertItem(ui->tabs, i, &it);
  }
  Settings s = hooks.settings ? *hooks.settings : Settings{};
  s.autostart = AutostartEnabled();
  if (hooks.settings) hooks.settings->autostart = s.autostart;
  for (int i = 0; i < 5; ++i) {
    ui->pages[i] = CreateWindowW(L"STATIC", L"", WS_CHILD, 16, 40, 430, 420, hwnd, nullptr,
                                 wc.hInstance, nullptr);
  }
  HWND p0 = ui->pages[0];
  MakeChk(p0, 8, 8, 360, 22, kAutostart, L"开机自启", s.autostart);
  MakeChk(p0, 8, 36, 360, 22, kRestore, L"启动时恢复翻译框", s.restore_boxes);
  MakeLbl(p0, 8, 70, 400, 40, L"界面语言：中文（本机）。深浅跟随系统。");
  HWND p1 = ui->pages[1];
  MakeRadio(p1, 8, 8, 200, 22, kEngAuto, L"自动", s.engine == EnginePref::Auto, true);
  MakeRadio(p1, 8, 32, 200, 22, kEngLocal, L"本地", s.engine == EnginePref::Local, false);
  MakeRadio(p1, 8, 56, 200, 22, kEngCloud, L"云端", s.engine == EnginePref::Cloud, false);
  MakeChk(p1, 220, 8, 180, 22, kPrivacy, L"隐私模式（仅本地）", s.privacy);
  MakeChk(p1, 220, 32, 180, 22, kQuality, L"质量档（beam=2）", s.quality);
  MakeLbl(p1, 8, 88, 400, 18, L"云端（全部留空则禁用，不预填网关）");
  MakeLbl(p1, 8, 110, 80, 18, L"Base URL");
  MakeEdit(p1, 90, 108, 320, 22, kBase, Utf8(s.cloud_base_url), false);
  MakeLbl(p1, 8, 138, 80, 18, L"API Key");
  MakeEdit(p1, 90, 136, 320, 22, kKey, Utf8(hooks.api_key ? *hooks.api_key : ""), true);
  MakeLbl(p1, 8, 166, 80, 18, L"Model");
  MakeEdit(p1, 90, 164, 320, 22, kModel, Utf8(s.cloud_model), false);
  MakeBtn(p1, 90, 196, 100, 26, kTest, L"测试连接");
  HWND p2 = ui->pages[2];
  MakeRadio(p2, 8, 8, 200, 22, kRendAuto, L"自动呈现", s.render == RenderLock::Auto, true);
  MakeRadio(p2, 8, 32, 200, 22, kRendSticker, L"锁定贴条", s.render == RenderLock::Sticker, false);
  MakeRadio(p2, 8, 56, 200, 22, kRendImm, L"锁定沉浸替换", s.render == RenderLock::Immersive, false);
  MakeChk(p2, 8, 80, 200, 22, kContrast, L"双语对照", s.contrast);
  MakeLbl(p2, 8, 112, 160, 18, L"贴条不透明度 60–100");
  MakeEdit(p2, 180, 110, 60, 22, kAlpha, std::to_wstring(s.sticker_alpha), false);
  MakeLbl(p2, 8, 140, 160, 18, L"字号缩放 80–150");
  MakeEdit(p2, 180, 138, 60, 22, kScale, std::to_wstring(s.font_scale), false);
  HWND p3 = ui->pages[3];
  ui->hk_mod[0] = s.mod_new;
  ui->hk_vk[0] = s.vk_new;
  ui->hk_mod[1] = s.mod_edit;
  ui->hk_vk[1] = s.vk_edit;
  ui->hk_mod[2] = s.mod_pause;
  ui->hk_vk[2] = s.vk_pause;
  ui->hk_mod[3] = s.mod_hide;
  ui->hk_vk[3] = s.vk_hide;
  ui->hk_mod[4] = s.mod_settings;
  ui->hk_vk[4] = s.vk_settings;
  MakeLbl(p3, 8, 8, 400, 36, L"点击「录入」后按下新组合。冲突会标在行上，仍可保存。冲突检测已做。");
  for (int i = 0; i < 5; ++i) {
    ui->hk_lbl[i] = MakeLbl(p3, 8, 50 + i * 48, 300, 22, L"");
    MakeBtn(p3, 320, 46 + i * 48, 80, 26, kHkBtn0 + i, L"录入");
  }
  RefreshHkLabels(ui);
  HWND p4 = ui->pages[4];
  wchar_t about[256];
  swprintf_s(about, L"LensTrans 0.2\n默认模型 Qwen2.5-0.5B Instruct Q4_K_M\n缓存 %zu 条 / %zu 字节\nApache-2.0 可覆盖 EU/UK/KR",
             hooks.cache_entries, hooks.cache_bytes);
  MakeLbl(p4, 8, 8, 400, 80, about);
  MakeBtn(p4, 8, 100, 120, 26, kClearCache, L"清理缓存");
  MakeLbl(p4, 8, 140, 400, 40, L"诊断日志：控制台窗口。不落盘原文。");
  ShowPage(ui, 0);
  MakeBtn(hwnd, 260, 488, 80, 26, kOk, L"确定");
  MakeBtn(hwnd, 352, 488, 80, 26, kCancel, L"取消");
  g_settings = hwnd;
  ShowWindow(hwnd, SW_SHOW);
}

bool FirstRun() {
  const std::string p = ConfigDir() + "\\settings.cfg";
  return GetFileAttributesA(p.c_str()) == INVALID_FILE_ATTRIBUTES;
}

HWND SettingsWindowHandle() { return g_settings; }

std::wstring CapturePermissionHint() {
  OSVERSIONINFOEXW os{};
  os.dwOSVersionInfoSize = sizeof(os);
  std::wstring ver = L"系统版本未读到。";
  using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  if (const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll")) {
    if (const auto fn = reinterpret_cast<RtlGetVersionFn>(GetProcAddress(ntdll, "RtlGetVersion"))) {
      if (fn(reinterpret_cast<OSVERSIONINFOW*>(&os)) == 0) {
        wchar_t buf[96];
        swprintf_s(buf, L"检测到 Windows %lu.%lu.%lu。", os.dwMajorVersion, os.dwMinorVersion,
                   os.dwBuildNumber);
        ver = buf;
        if (os.dwMajorVersion < 10 || (os.dwMajorVersion == 10 && os.dwBuildNumber < 19041))
          ver += L" 低于 2004，WGC 可能不可用，将走 BitBlt/PrintWindow 兜底。";
        else
          ver += L" 支持 WGC。";
      }
    }
  } else {
    ver = L"检测失败：无法查询 ntdll。权限状态未知，不阻止下一步。";
  }
  ver +=
      L"\n\n本步未发起屏幕捕获，因此不会弹出系统权限框。\n"
      L"授权状态无稳定公开 API 可读。若已在「设置 → 隐私和安全性 → 屏幕截图和屏幕录制」允许本应用，"
      L"捕获即可用；若稍后首次抓屏弹出「屏幕录制」，请点允许。";
  return ver;
}

void PaintOnbStep(OnbUi* o) {
  if (!o || !o->body) return;
  const wchar_t* title = L"";
  std::wstring body;
  if (o->step == 0) {
    title = L"LensTrans 引导 1/3 — 欢迎";
    body =
        L"欢迎使用 LensTrans。\n\n"
        L"默认完全离线运行，不收集数据、不预填云端网关。\n"
        L"数据流：屏幕捕获 → 本机 OCR → 本机模型或你自行填写的 OpenAI 兼容云端。\n\n"
        L"下一步检测屏幕访问能力（不发起抓屏）。";
    if (o->local) ShowWindow(o->local, SW_HIDE);
    EnableWindow(o->back, FALSE);
    SetWindowTextW(o->next, L"下一步");
  } else if (o->step == 1) {
    title = L"LensTrans 引导 2/3 — 屏幕访问";
    body = L"Windows 屏幕访问\n\n" + CapturePermissionHint();
    if (o->local) ShowWindow(o->local, SW_HIDE);
    EnableWindow(o->back, TRUE);
    SetWindowTextW(o->next, L"下一步");
  } else {
    title = L"LensTrans 引导 3/3 — 本地引擎";
    body =
        L"默认使用已下载的 Qwen2.5-0.5B Instruct Q4_K_M（约 491MB）。\n"
        L"云端 Base URL / API Key / Model 全部留空。\n\n"
        L"勾选后本机加载模型；不勾选仍创建翻译框，但不加载模型。";
    if (o->local) ShowWindow(o->local, SW_SHOW);
    EnableWindow(o->back, TRUE);
    SetWindowTextW(o->next, L"完成");
  }
  SetWindowTextW(GetParent(o->body), title);
  SetWindowTextW(o->body, body.c_str());
}

LRESULT CALLBACK OnbProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  auto* o = reinterpret_cast<OnbUi*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (msg) {
    case WM_COMMAND:
      if (!o) return 0;
      if (LOWORD(wp) == kOnbCancel) {
        o->done = true;
        o->ok = false;
        DestroyWindow(hwnd);
      } else if (LOWORD(wp) == kOnbBack && o->step > 0) {
        --o->step;
        PaintOnbStep(o);
      } else if (LOWORD(wp) == kOnbNext) {
        if (o->step < 2) {
          ++o->step;
          PaintOnbStep(o);
        } else {
          if (o->hooks && o->hooks->settings) {
            o->hooks->settings->download_model =
                o->local && SendMessageW(o->local, BM_GETCHECK, 0, 0) == BST_CHECKED;
          }
          SaveSettingsFile(ConfigDir() + "\\settings.cfg",
                           o->hooks && o->hooks->settings ? *o->hooks->settings : Settings{});
          o->done = true;
          o->ok = true;
          DestroyWindow(hwnd);
        }
      }
      return 0;
    case WM_CLOSE:
      if (o) {
        o->done = true;
        o->ok = false;
      }
      DestroyWindow(hwnd);
      return 0;
    default:
      return DefWindowProcW(hwnd, msg, wp, lp);
  }
}

bool ShowOnboarding(HWND owner, AppHooks& hooks) {
  WNDCLASSW wc{};
  wc.lpfnWndProc = OnbProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wc.lpszClassName = L"LensTransOnboard";
  RegisterClassW(&wc);
  const int sw = GetSystemMetrics(SM_CXSCREEN);
  const int sh = GetSystemMetrics(SM_CYSCREEN);
  HWND hwnd = CreateWindowExW(WS_EX_DLGMODALFRAME, L"LensTransOnboard", L"LensTrans 引导",
                              WS_POPUP | WS_CAPTION | WS_SYSMENU, (sw - 640) / 2, (sh - 420) / 2, 640,
                              420, owner, nullptr, wc.hInstance, nullptr);
  if (!hwnd) return false;
  OnbUi ui{};
  ui.hooks = &hooks;
  ui.body = MakeLbl(hwnd, 24, 16, 592, 280, L"");
  const bool want_local = !hooks.settings || hooks.settings->download_model;
  ui.local = MakeChk(hwnd, 24, 300, 280, 24, kOnbLocal, L"使用本地模型（推荐）", want_local);
  ui.back = MakeBtn(hwnd, 352, 348, 80, 28, kOnbBack, L"上一步");
  ui.next = MakeBtn(hwnd, 444, 348, 80, 28, kOnbNext, L"下一步");
  MakeBtn(hwnd, 536, 348, 80, 28, kOnbCancel, L"取消");
  SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&ui));
  PaintOnbStep(&ui);
  ShowWindow(hwnd, SW_SHOW);
  EnableWindow(owner, FALSE);
  MSG msg{};
  while (!ui.done && GetMessageW(&msg, nullptr, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  EnableWindow(owner, TRUE);
  return ui.ok;
}

HWND ShowOnboardingProbe(HWND owner, AppHooks& hooks) {
  WNDCLASSW wc{};
  wc.lpfnWndProc = OnbProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wc.lpszClassName = L"LensTransOnboard";
  RegisterClassW(&wc);
  const int sw = GetSystemMetrics(SM_CXSCREEN);
  const int sh = GetSystemMetrics(SM_CYSCREEN);
  HWND hwnd = CreateWindowExW(WS_EX_DLGMODALFRAME, L"LensTransOnboard", L"LensTrans 引导",
                              WS_POPUP | WS_CAPTION | WS_SYSMENU, (sw - 640) / 2, (sh - 420) / 2, 640,
                              420, owner, nullptr, wc.hInstance, nullptr);
  if (!hwnd) return nullptr;
  auto* ui = new OnbUi{};
  ui->hooks = &hooks;
  ui->body = MakeLbl(hwnd, 24, 16, 592, 280, L"");
  const bool want_local = !hooks.settings || hooks.settings->download_model;
  ui->local = MakeChk(hwnd, 24, 300, 280, 24, kOnbLocal, L"使用本地模型（推荐）", want_local);
  ui->back = MakeBtn(hwnd, 352, 348, 80, 28, kOnbBack, L"上一步");
  ui->next = MakeBtn(hwnd, 444, 348, 80, 28, kOnbNext, L"下一步");
  MakeBtn(hwnd, 536, 348, 80, 28, kOnbCancel, L"取消");
  SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(ui));
  PaintOnbStep(ui);
  ShowWindow(hwnd, SW_SHOW);
  UpdateWindow(hwnd);
  g_onboard = hwnd;
  g_onboard_ui = ui;
  return hwnd;
}

HWND OnboardingWindowHandle() { return g_onboard; }

}  // namespace lenstrans::win
