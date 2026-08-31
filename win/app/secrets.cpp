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
#include <filesystem>
#include <cctype>
#include <system_error>
#include <string>
#include <vector>

#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

namespace lenstrans::win {

static std::string NarrowPath(const wchar_t* w);
static std::wstring WidePath(const std::string& s);
static bool WriteAtomic(const std::string& path, const void* data, std::size_t size);

std::string ConfigDir() {
  PWSTR known = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &known))) return {};
  const std::wstring base(known);
  CoTaskMemFree(known);
  if (base.empty()) return {};
  const std::wstring dir = base + L"\\LensTrans";
  if (!CreateDirectoryW(dir.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return {};
  return NarrowPath(dir.c_str());
}

std::string ConfigPath(const char* file_name) {
  if (!file_name || !*file_name) return {};
  for (const char* p = file_name; *p; ++p) {
    const unsigned char c = static_cast<unsigned char>(*p);
    if (!(std::isalnum(c) || c == '.' || c == '_' || c == '-')) return {};
  }
  const std::string dir = ConfigDir();
  return dir.empty() ? std::string{} : dir + "\\" + file_name;
}

bool WriteConfigFile(const char* file_name, const std::string& body) {
  const std::string path = ConfigPath(file_name);
  return !path.empty() && WriteAtomic(path, body.data(), body.size());
}

bool ProtectToFile(const std::string& path, const std::string& plain) {
  DATA_BLOB in{}, out{};
  in.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(plain.data()));
  in.cbData = static_cast<DWORD>(plain.size());
  if (!CryptProtectData(&in, L"LensTrans", nullptr, nullptr, nullptr, 0, &out)) return false;
  const bool ok = WriteAtomic(path, out.pbData, out.cbData);
  LocalFree(out.pbData);
  return ok;
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
  if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w, -1, s.data(), static_cast<int>(s.size()), nullptr, nullptr);
  return s;
}

static std::wstring WidePath(const std::string& s) {
  if (s.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring w(static_cast<std::size_t>(n ? n - 1 : 0), 0);
  if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), static_cast<int>(w.size()));
  return w;
}

static bool WriteAtomic(const std::string& path, const void* data, std::size_t size) {
  const std::wstring wide = WidePath(path);
  if (wide.empty() || size > MAXDWORD) return false;
  const std::wstring temp = wide + L".tmp." + std::to_wstring(GetCurrentProcessId()) + L"." +
                            std::to_wstring(GetTickCount64());
  HANDLE file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                             FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  const BOOL ok = size == 0 || (WriteFile(file, data, static_cast<DWORD>(size), &written, nullptr) &&
                                written == size);
  FlushFileBuffers(file);
  CloseHandle(file);
  if (!ok) {
    DeleteFileW(temp.c_str());
    return false;
  }
  if (!MoveFileExW(temp.c_str(), wide.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temp.c_str());
    return false;
  }
  return true;
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
