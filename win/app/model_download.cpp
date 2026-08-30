#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#include "win/app/model_download.hpp"
#include "lenstrans/model_meta.hpp"
#include "lenstrans/paths.hpp"

#include <windows.h>
#include <bcrypt.h>
#include <winhttp.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(lib, "winhttp.lib")
#pragma comment(lib, "bcrypt.lib")

namespace lenstrans::win {
namespace {

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(static_cast<std::size_t>(n), 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

bool CrackUrl(const std::string& url, std::wstring& host, std::wstring& path, INTERNET_PORT& port,
              bool& https) {
  URL_COMPONENTSW uc{};
  uc.dwStructSize = sizeof(uc);
  wchar_t host_buf[256]{};
  wchar_t path_buf[2048]{};
  uc.lpszHostName = host_buf;
  uc.dwHostNameLength = 256;
  uc.lpszUrlPath = path_buf;
  uc.dwUrlPathLength = 2048;
  const std::wstring w = Utf8ToWide(url);
  if (!WinHttpCrackUrl(w.c_str(), static_cast<DWORD>(w.size()), 0, &uc)) return false;
  host.assign(uc.lpszHostName, uc.dwHostNameLength);
  path.assign(uc.lpszUrlPath, uc.dwUrlPathLength);
  if (uc.dwExtraInfoLength && uc.lpszExtraInfo) path.append(uc.lpszExtraInfo, uc.dwExtraInfoLength);
  if (path.empty()) path = L"/";
  port = uc.nPort;
  https = uc.nScheme == INTERNET_SCHEME_HTTPS;
  return !host.empty();
}

std::string Sha256FileHex(const std::string& path) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return {};
  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  if (BCryptOpenAlgorithmProvider(&alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) return {};
  DWORD obj_len = 0, cb = 0, hash_len = 0;
  BCryptGetProperty(alg, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&obj_len), sizeof(obj_len),
                    &cb, 0);
  BCryptGetProperty(alg, BCRYPT_HASH_LENGTH, reinterpret_cast<PUCHAR>(&hash_len), sizeof(hash_len),
                    &cb, 0);
  std::vector<UCHAR> obj(obj_len), digest(hash_len);
  if (BCryptCreateHash(alg, &hash, obj.data(), obj_len, nullptr, 0, 0) < 0) {
    BCryptCloseAlgorithmProvider(alg, 0);
    return {};
  }
  char buf[1 << 16];
  while (f) {
    f.read(buf, sizeof(buf));
    const auto n = static_cast<DWORD>(f.gcount());
    if (n && BCryptHashData(hash, reinterpret_cast<PUCHAR>(buf), n, 0) < 0) {
      BCryptDestroyHash(hash);
      BCryptCloseAlgorithmProvider(alg, 0);
      return {};
    }
  }
  if (BCryptFinishHash(hash, digest.data(), hash_len, 0) < 0) {
    BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(alg, 0);
    return {};
  }
  BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(alg, 0);
  static const char* hex = "0123456789abcdef";
  std::string out;
  out.resize(digest.size() * 2);
  for (size_t i = 0; i < digest.size(); ++i) {
    out[i * 2] = hex[digest[i] >> 4];
    out[i * 2 + 1] = hex[digest[i] & 0xf];
  }
  return out;
}

std::uint64_t FileSize(const std::string& path) {
  WIN32_FILE_ATTRIBUTE_DATA fad{};
  if (!GetFileAttributesExA(path.c_str(), GetFileExInfoStandard, &fad)) return 0;
  ULARGE_INTEGER u;
  u.HighPart = fad.nFileSizeHigh;
  u.LowPart = fad.nFileSizeLow;
  return u.QuadPart;
}

bool HttpDownloadRange(const std::string& url, const std::string& part_path,
                       std::uint64_t expected_total,
                       const std::function<void(const ModelDownloadProgress&)>& on_progress,
                       std::string& error_out) {
  std::wstring host, path;
  INTERNET_PORT port = 443;
  bool https = true;
  if (!CrackUrl(url, host, path, port, https)) {
    error_out = "bad url";
    return false;
  }
  HINTERNET session = WinHttpOpen(L"LensTrans/0.2", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                  WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) {
    error_out = "WinHttpOpen failed";
    return false;
  }
  WinHttpSetTimeouts(session, 10000, 15000, 30000, 60000);
  HINTERNET conn = WinHttpConnect(session, host.c_str(), port, 0);
  if (!conn) {
    WinHttpCloseHandle(session);
    error_out = "connect failed";
    return false;
  }
  const DWORD flags = https ? WINHTTP_FLAG_SECURE : 0;
  HINTERNET req = WinHttpOpenRequest(conn, L"GET", path.c_str(), nullptr, WINHTTP_NO_REFERER,
                                     WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (!req) {
    WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
    error_out = "open request failed";
    return false;
  }

  const std::uint64_t have = FileSize(part_path);
  std::wstring range;
  if (have > 0 && have < expected_total) {
    range = L"Range: bytes=" + std::to_wstring(have) + L"-";
  }

  BOOL ok = WinHttpSendRequest(req, range.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : range.c_str(),
                               range.empty() ? 0 : static_cast<DWORD>(-1L), WINHTTP_NO_REQUEST_DATA, 0,
                               0, 0) &&
            WinHttpReceiveResponse(req, nullptr);
  if (!ok) {
    WinHttpCloseHandle(req);
    WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
    error_out = "http send failed";
    return false;
  }

  DWORD status = 0;
  DWORD status_sz = sizeof(status);
  WinHttpQueryHeaders(req, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                      WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_sz, WINHTTP_NO_HEADER_INDEX);
  if (status != 200 && status != 206) {
    WinHttpCloseHandle(req);
    WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
    error_out = "http status " + std::to_string(status);
    return false;
  }

  const bool append = (status == 206);
  std::ofstream out(part_path, append ? (std::ios::binary | std::ios::app) : std::ios::binary);
  if (!out) {
    WinHttpCloseHandle(req);
    WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
    error_out = "cannot write part file";
    return false;
  }

  std::uint64_t done = append ? have : 0;
  std::vector<char> buf(1 << 16);
  DWORD got = 0;
  while (WinHttpReadData(req, buf.data(), static_cast<DWORD>(buf.size()), &got) && got) {
    out.write(buf.data(), got);
    done += got;
    if (on_progress) {
      ModelDownloadProgress p;
      p.bytes_done = done;
      p.bytes_total = expected_total;
      p.phase = "fetch";
      on_progress(p);
    }
  }
  out.close();
  WinHttpCloseHandle(req);
  WinHttpCloseHandle(conn);
  WinHttpCloseHandle(session);
  if (done < expected_total) {
    error_out = "incomplete download";
    return false;
  }
  return true;
}

}  // namespace

bool VerifyDefaultGguf(const std::string& dest_path, std::string& error_out) {
  const auto sz = FileSize(dest_path);
  if (sz != kDefaultGgufBytes) {
    error_out = "size mismatch: " + std::to_string(sz);
    return false;
  }
  const std::string hex = Sha256FileHex(dest_path);
  if (!IsDefaultGgufSha256(hex)) {
    error_out = "sha256 mismatch: " + hex;
    return false;
  }
  return true;
}

bool DownloadDefaultGguf(const std::string& dest_path,
                         const std::function<void(const ModelDownloadProgress&)>& on_progress,
                         std::string& error_out) {
  EnsureDir(std::filesystem::path(dest_path).parent_path().string());
  {
    std::string verr;
    if (VerifyDefaultGguf(dest_path, verr)) {
      if (on_progress) {
        ModelDownloadProgress p;
        p.bytes_done = kDefaultGgufBytes;
        p.bytes_total = kDefaultGgufBytes;
        p.phase = "done";
        p.detail = "already present";
        on_progress(p);
      }
      return true;
    }
  }

  const std::string part = dest_path + ".part";
  const char* urls[] = {kDefaultGgufUrlModelscope, kDefaultGgufUrlHuggingFace};
  bool fetched = false;
  for (const char* url : urls) {
    std::string err;
    if (HttpDownloadRange(url, part, kDefaultGgufBytes, on_progress, err)) {
      fetched = true;
      break;
    }
    error_out = err;
  }
  if (!fetched) return false;

  if (on_progress) {
    ModelDownloadProgress p;
    p.bytes_done = kDefaultGgufBytes;
    p.bytes_total = kDefaultGgufBytes;
    p.phase = "hash";
    on_progress(p);
  }
  std::string verr;
  if (!VerifyDefaultGguf(part, verr)) {
    DeleteFileA(part.c_str());
    error_out = verr;
    if (on_progress) {
      ModelDownloadProgress p;
      p.phase = "error";
      p.detail = verr;
      on_progress(p);
    }
    return false;
  }
  DeleteFileA(dest_path.c_str());
  if (!MoveFileA(part.c_str(), dest_path.c_str())) {
    error_out = "rename failed";
    return false;
  }
  if (on_progress) {
    ModelDownloadProgress p;
    p.bytes_done = kDefaultGgufBytes;
    p.bytes_total = kDefaultGgufBytes;
    p.phase = "done";
    on_progress(p);
  }
  WriteTextFile(JoinPath(EvalOutDir(), "download-status.md"),
                std::string("# download-status\n\n- file: `") + dest_path +
                    "`\n- bytes: " + std::to_string(kDefaultGgufBytes) +
                    "\n- sha256: `" + kDefaultGgufSha256 + "`\n- result: **ok**\n");
  return true;
}

}  // namespace lenstrans::win
