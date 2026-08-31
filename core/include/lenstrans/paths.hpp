#pragma once

#include "lenstrans/model_meta.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace lenstrans {

inline std::string ExeDir() {
#ifdef _WIN32
  char buf[MAX_PATH]{};
  const DWORD n = GetModuleFileNameA(nullptr, buf, MAX_PATH);
  if (!n) return ".";
  return std::filesystem::path(buf).parent_path().string();
#else
  std::error_code ec;
  auto p = std::filesystem::read_symlink("/proc/self/exe", ec);
  if (ec) return ".";
  return p.parent_path().string();
#endif
}

inline bool FileExists(const std::string& path) {
  std::error_code ec;
  return std::filesystem::is_regular_file(path, ec);
}

inline std::string JoinPath(const std::string& a, const std::string& b) {
  return (std::filesystem::path(a) / b).string();
}

// Prefer LENSTRANS_ROOT, then walk up from exe looking for CMakeLists.txt + models/.
inline std::string DetectRepoRoot() {
  if (const char* env = std::getenv("LENSTRANS_ROOT"); env && *env) {
    if (FileExists(JoinPath(env, "CMakeLists.txt"))) return env;
  }
  std::filesystem::path cur = ExeDir();
  for (int i = 0; i < 8; ++i) {
    if (std::filesystem::exists(cur / "CMakeLists.txt") &&
        std::filesystem::exists(cur / "models")) {
      return cur.string();
    }
    if (!cur.has_parent_path() || cur == cur.root_path()) break;
    cur = cur.parent_path();
  }
  return ExeDir();
}

inline std::string EvalOutDir() {
  if (const char* env = std::getenv("LENSTRANS_EVAL_OUT"); env && *env) return env;
  return JoinPath(DetectRepoRoot(), "tools/eval/out");
}

inline bool EnsureDir(const std::string& dir) {
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  return !ec;
}

inline std::string FindDefaultModelPath(const std::string& override_path = {}) {
  if (!override_path.empty() && FileExists(override_path)) return override_path;
  const std::string name = kDefaultGgufFileName;
  const std::string root = DetectRepoRoot();
  const std::string exe = ExeDir();
  const std::vector<std::string> cands = {
      JoinPath(root, JoinPath("models", name)),
      JoinPath(exe, name),
      JoinPath(exe, JoinPath("models", name)),
      JoinPath(JoinPath(exe, ".."), JoinPath("models", name)),
      JoinPath(JoinPath(exe, "../.."), JoinPath("models", name)),
  };
  for (const auto& p : cands) {
    if (FileExists(p)) return p;
  }
  return JoinPath(root, JoinPath("models", name));
}

inline std::string FindLlamaCliPath() {
  const std::string root = DetectRepoRoot();
  const std::string exe = ExeDir();
  const std::vector<std::string> cands = {
      JoinPath(root, "third_party/llama.cpp/build/bin/Release/llama-cli.exe"),
      JoinPath(root, "third_party/llama.cpp/build/bin/llama-cli"),
      JoinPath(exe, "llama-cli.exe"),
      JoinPath(exe, "llama-cli"),
  };
  for (const auto& p : cands) {
    if (FileExists(p)) return p;
  }
  return {};
}

inline bool WriteTextFile(const std::string& path, const std::string& body) {
  EnsureDir(std::filesystem::path(path).parent_path().string());
  std::ofstream f(path, std::ios::binary);
  if (!f) return false;
  f << body;
  return static_cast<bool>(f);
}

}  // namespace lenstrans
