#include "lenstrans/cloud_http.hpp"
#include "lenstrans/engine.hpp"

#ifdef _WIN32
#ifndef UNICODE
#define UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#endif

#include <chrono>
#include <memory>
#include <string>

namespace lenstrans {
namespace {

#ifdef _WIN32

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return {};
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(static_cast<std::size_t>(n), 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

bool ParseUrl(const std::string& base, std::wstring& host, std::wstring& path, INTERNET_PORT& port,
              bool& https) {
  URL_COMPONENTSW uc{};
  uc.dwStructSize = sizeof(uc);
  wchar_t host_buf[256]{};
  wchar_t path_buf[1024]{};
  uc.lpszHostName = host_buf;
  uc.dwHostNameLength = 256;
  uc.lpszUrlPath = path_buf;
  uc.dwUrlPathLength = 1024;
  const std::wstring w = Utf8ToWide(base);
  if (!WinHttpCrackUrl(w.c_str(), static_cast<DWORD>(w.size()), 0, &uc)) return false;
  host.assign(uc.lpszHostName, uc.dwHostNameLength);
  path.assign(uc.lpszUrlPath, uc.dwUrlPathLength);
  if (path.empty()) path = L"/";
  if (path.back() == L'/') path += L"chat/completions";
  else path += L"/chat/completions";
  port = uc.nPort;
  https = uc.nScheme == INTERNET_SCHEME_HTTPS;
  return !host.empty();
}

TranslateResult PostOnce(const std::wstring& host, const std::wstring& path, INTERNET_PORT port,
                         bool https, const std::string& key, const std::string& body) {
  TranslateResult r;
  r.engine = EngineKind::Cloud;
  HINTERNET session = WinHttpOpen(L"LensTrans/0.2", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                  WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) {
    r.error = "http send failed";
    return r;
  }
  const CloudTimeoutsMs t;
  WinHttpSetTimeouts(session, t.resolve, t.connect, t.send, t.receive);
  HINTERNET conn = WinHttpConnect(session, host.c_str(), port, 0);
  if (!conn) {
    WinHttpCloseHandle(session);
    r.error = "connect failed";
    return r;
  }
  DWORD flags = https ? WINHTTP_FLAG_SECURE : 0;
  HINTERNET reqh = WinHttpOpenRequest(conn, L"POST", path.c_str(), nullptr, WINHTTP_NO_REFERER,
                                      WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (!reqh) {
    WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
    r.error = "http send failed";
    return r;
  }
  const std::wstring hdr = L"Content-Type: application/json\r\nAuthorization: Bearer " +
                           Utf8ToWide(key);
  const BOOL sent = WinHttpSendRequest(reqh, hdr.c_str(), static_cast<DWORD>(hdr.size()),
                                       (LPVOID)body.data(), static_cast<DWORD>(body.size()),
                                       static_cast<DWORD>(body.size()), 0) &&
                    WinHttpReceiveResponse(reqh, nullptr);
  if (!sent) {
    WinHttpCloseHandle(reqh);
    WinHttpCloseHandle(conn);
    WinHttpCloseHandle(session);
    r.error = "http send failed";
    return r;
  }
  std::string acc;
  DWORD avail = 0;
  while (WinHttpQueryDataAvailable(reqh, &avail) && avail) {
    std::string chunk(avail, 0);
    DWORD got = 0;
    if (!WinHttpReadData(reqh, chunk.data(), avail, &got)) break;
    chunk.resize(got);
    acc += chunk;
  }
  WinHttpCloseHandle(reqh);
  WinHttpCloseHandle(conn);
  WinHttpCloseHandle(session);
  r.text = ParseChatCompletionBody(acc);
  if (r.text.empty()) r.error = "empty cloud output";
  return r;
}

class CloudEngine final : public IEngine {
 public:
  CloudEngine(std::string base, std::string key, std::string model)
      : base_(std::move(base)), key_(std::move(key)), model_(std::move(model)) {}

  bool Ready() const override { return !base_.empty() && !key_.empty() && !model_.empty(); }

  TranslateResult Translate(const TranslateRequest& req) override {
    TranslateResult r;
    r.engine = EngineKind::Cloud;
    const auto t0 = std::chrono::steady_clock::now();
    if (!Ready()) {
      r.error = "cloud not configured";
      return r;
    }
    std::wstring host, path;
    INTERNET_PORT port = 443;
    bool https = true;
    if (!ParseUrl(base_, host, path, port, https)) {
      r.error = "bad base url";
      return r;
    }
    const std::string body =
        BuildChatCompletionsJson(model_, BuildTranslatePrompt(req), true);
    r = PostOnce(host, path, port, https, key_, body);
    if ((r.text.empty() || !r.error.empty()) && ShouldRetryCloud(r.error)) {
      r = PostOnce(host, path, port, https, key_, body);
    }
    r.engine = EngineKind::Cloud;
    r.latency_ms = static_cast<int>(
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0)
            .count());
    return r;
  }

 private:
  std::string base_, key_, model_;
};

#endif

class UnconfiguredCloudEngine final : public IEngine {
 public:
  bool Ready() const override { return false; }
  TranslateResult Translate(const TranslateRequest&) override {
    TranslateResult r;
    r.engine = EngineKind::Cloud;
    r.error = "cloud not configured";
    return r;
  }
};

}  // namespace

std::unique_ptr<IEngine> MakeCloudEngine(const std::string& base_url, const std::string& api_key,
                                         const std::string& model) {
#ifdef _WIN32
  return std::make_unique<CloudEngine>(base_url, api_key, model);
#else
  (void)base_url;
  (void)api_key;
  (void)model;
  return std::make_unique<UnconfiguredCloudEngine>();
#endif
}

}  // namespace lenstrans
