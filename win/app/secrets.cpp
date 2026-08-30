#ifndef UNICODE
#define UNICODE
#endif

#include "win/app/secrets.hpp"
#include "lenstrans/autostart.hpp"

#include <windows.h>
#include <wincrypt.h>
#include <dpapi.h>
#include <shlobj.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")

#include <fstream>
#include <string>
#include <vector>

#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

namespace lenstrans::win {

std::string ConfigDir() {
  char path[MAX_PATH]{};
  if (FAILED(SHGetFolderPathA(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, path))) return ".";
  std::string dir = std::string(path) + "\\LensTrans";
  CreateDirectoryA(dir.c_str(), nullptr);
  return dir;
}

bool ProtectToFile(const std::string& path, const std::string& plain) {
  DATA_BLOB in{}, out{};
  in.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(plain.data()));
  in.cbData = static_cast<DWORD>(plain.size());
  if (!CryptProtectData(&in, L"LensTrans", nullptr, nullptr, nullptr, 0, &out)) return false;
  std::ofstream f(path, std::ios::binary);
  if (!f) {
    LocalFree(out.pbData);
    return false;
  }
  f.write(reinterpret_cast<char*>(out.pbData), out.cbData);
  LocalFree(out.pbData);
  return true;
}

bool UnprotectFromFile(const std::string& path, std::string& plain) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  std::vector<char> buf((std::istreambuf_iterator<char>(f)), {});
  if (buf.empty()) return false;
  DATA_BLOB in{}, out{};
  in.pbData = reinterpret_cast<BYTE*>(buf.data());
  in.cbData = static_cast<DWORD>(buf.size());
  if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr, 0, &out)) return false;
  plain.assign(reinterpret_cast<char*>(out.pbData), out.cbData);
  LocalFree(out.pbData);
  return true;
}

static std::string NarrowPath(const wchar_t* w) {
  if (!w || !w[0]) return {};
  const int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
  std::string s(static_cast<std::size_t>(n ? n - 1 : 0), 0);
  if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w, -1, s.data(), n, nullptr, nullptr);
  return s;
}

static std::wstring WidePath(const std::string& s) {
  if (s.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring w(static_cast<std::size_t>(n ? n - 1 : 0), 0);
  if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), n);
  return w;
}

void SetAutostart(bool on) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                      nullptr, 0, KEY_SET_VALUE | KEY_QUERY_VALUE, nullptr, &key, nullptr) !=
      ERROR_SUCCESS) {
    return;
  }
  if (on) {
    wchar_t exe[MAX_PATH]{};
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    const std::wstring q = WidePath(QuoteRunPath(NarrowPath(exe)));
    RegSetValueExW(key, L"LensTrans", 0, REG_SZ, reinterpret_cast<const BYTE*>(q.c_str()),
                   static_cast<DWORD>((q.size() + 1) * sizeof(wchar_t)));
  } else {
    RegDeleteValueW(key, L"LensTrans");
  }
  RegCloseKey(key);
}

std::string ProbeCloud(const std::string& base_url, const std::string& model) {
  if (base_url.empty() || model.empty()) return "disabled: empty base url or model";
  URL_COMPONENTSW uc{};
  uc.dwStructSize = sizeof(uc);
  wchar_t host[256]{};
  wchar_t path[1024]{};
  uc.lpszHostName = host;
  uc.dwHostNameLength = 256;
  uc.lpszUrlPath = path;
  uc.dwUrlPathLength = 1024;
  const int n = MultiByteToWideChar(CP_UTF8, 0, base_url.c_str(), -1, nullptr, 0);
  std::wstring w(static_cast<std::size_t>(n), 0);
  MultiByteToWideChar(CP_UTF8, 0, base_url.c_str(), -1, w.data(), n);
  if (!WinHttpCrackUrl(w.c_str(), 0, 0, &uc)) return "bad url";
  HINTERNET s = WinHttpOpen(L"LensTrans/0.2", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!s) return "WinHttpOpen failed";
  WinHttpSetTimeouts(s, 3000, 3000, 3000, 3000);
  HINTERNET c = WinHttpConnect(s, host, uc.nPort, 0);
  if (!c) {
    WinHttpCloseHandle(s);
    return "connect failed";
  }
  WinHttpCloseHandle(c);
  WinHttpCloseHandle(s);
  return "ok";
}

bool AutostartEnabled() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Run", 0,
                    KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
    return false;
  }
  wchar_t buf[MAX_PATH + 8]{};
  DWORD type = 0, cb = sizeof(buf);
  const LONG st = RegQueryValueExW(key, L"LensTrans", nullptr, &type, reinterpret_cast<BYTE*>(buf), &cb);
  RegCloseKey(key);
  return st == ERROR_SUCCESS && type == REG_SZ && buf[0] != 0;
}

}  // namespace lenstrans::win
